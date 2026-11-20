//// The poller that reads the state script for the Overview: one process for the
//// whole dashboard, reading while at least one page is subscribed and never
//// otherwise.
////
//// ```text
//// page runtime ──subscribe──► poller ──start_read──► script runner (a process of its own)
////      ▲                        │  ▲                        │
////      └──── Reading ───────────┘  └──── read ended ────────┘
//// timer ──tick──► poller            timer ──deadline──► poller
//// ```
////
//// - The first page to subscribe starts the interval timer and a read, unless one
////   is still running; a page that subscribes later is handed the latest
////   reading at once. When the last page leaves, the timer stops and the latest
////   reading is dropped, so the next page waits for a read and is never handed
////   an old one. A read that runs when the last page leaves goes on, and a page
////   that subscribes before it ends waits for its answer: two reads never run
////   at once.
//// - A read that ends or passes its deadline while no page is subscribed is
////   dropped.
//// - A tick of an earlier timer chain is dropped (`subscribers`), so a page that
////   leaves and returns never doubles the interval.
//// - A tick while a read runs starts no second read; it only lets a read that
////   has run too long show the facts last read as stale (`host_reading`).
//// - A read that has not ended at the deadline is sent as stale with that
////   reason; its answer, if it comes, is dropped.
//// - A page that ends is dropped by the poller's own monitor of its runtime.
//// - The poller keeps no state a restart cannot rebuild: pages subscribe again
////   when their runtimes are rebuilt (the supervisor restarts both together).

import genesis_prime/dashboard/host_reading.{type Reading, Ran, Waiting}
import genesis_prime/dashboard/script
import genesis_prime/dashboard/subscribers.{type Subscribers}
import gleam/bool
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision

/// How often the poller reads while a page is subscribed: 2 s, a guess (a read
/// takes 0.6 to 1.6 s, so the page is never more than a read and an interval
/// behind).
pub const interval_ms = 2000

/// How long a read may run before it is ended and shown as failed: 15 s, a
/// guess (a read takes 0.6 to 1.6 s, and `state.sh` ends each of its commands
/// after 3 s).
pub const deadline_ms = 15_000

/// How long the supervisor waits for the poller to stop.
const shutdown_ms = 1000

/// How long the start waits for the poller's initialiser.
const initialiser_ms = 1000

/// What the poller is told. Pages and tests send these through this module's
/// functions.
pub opaque type Message {
  Subscribe(subscriber: Subject(Reading))
  Unsubscribe(subscriber: Subject(Reading))
  Tick(chain: Int)
  PollNow
  SubscriberDown(down: process.Down)
  ReadEnded(read: Int, result: Result(script.Finished, script.Failure))
  ReadDeadline(read: Int)
  DeadlineNow
  CountSubscribers(reply: Subject(Int))
}

/// What the poller does and when.
///
/// `start_read` starts one read and gives its answer to the function it is
/// handed, from any process; it must not wait for the read. `now_ms` is the
/// clock the readings are stamped by. `arm` arms the interval timer
/// (`subscribers.send_after`, or a test's own).
pub type Settings {
  Settings(
    start_read: fn(fn(Result(script.Finished, script.Failure)) -> Nil) -> Nil,
    now_ms: fn() -> Int,
    interval_ms: Int,
    deadline_ms: Int,
    arm: subscribers.Arm(Message),
  )
}

/// The read in flight and the timer of its deadline.
type Read {
  Read(id: Int, deadline: process.Timer)
}

type State {
  State(
    self: Subject(Message),
    settings: Settings,
    subscribers: Subscribers(Reading, Message),
    latest: Option(Reading),
    read: Option(Read),
    next_read: Int,
  )
}

/// A read that runs the script at `path` in a process of its own, linked to
/// the caller, under the runner's deadline.
pub fn script_reader(
  path path: String,
  environment environment: List(#(String, String)),
  deadline_ms deadline_ms: Int,
) -> fn(fn(Result(script.Finished, script.Failure)) -> Nil) -> Nil {
  fn(answer) {
    let _reader =
      process.spawn(fn() {
        answer(script.run(path:, environment:, deadline_ms:))
      })
    Nil
  }
}

fn builder(
  settings: Settings,
) -> actor.Builder(State, Message, Subject(Message)) {
  actor.new_with_initialiser(initialiser_ms, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(SubscriberDown)
    State(
      self:,
      settings:,
      subscribers: subscribers.new(
        owner: self,
        interval_ms: settings.interval_ms,
        arm: settings.arm,
        tick: Tick,
      ),
      latest: None,
      read: None,
      next_read: 0,
    )
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
}

/// Starts a poller linked to the caller.
pub fn start(
  settings settings: Settings,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.start(builder(settings))
}

/// The poller as a child of a supervisor, registered under `name` so that a
/// restarted poller is reached by the same subject.
pub fn supervised(
  settings settings: Settings,
  name name: Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { actor.start(actor.named(builder(settings), name)) })
  |> supervision.timeout(shutdown_ms)
}

/// Subscribes a page: it is sent a reading each time one is made, and the latest
/// at once when there is one.
pub fn subscribe(
  host host: Subject(Message),
  subscriber subscriber: Subject(Reading),
) -> Nil {
  process.send(host, Subscribe(subscriber:))
}

/// Takes a page's subscription back.
pub fn unsubscribe(
  host host: Subject(Message),
  subscriber subscriber: Subject(Reading),
) -> Nil {
  process.send(host, Unsubscribe(subscriber:))
}

/// A tick without the timer: reads now when a page is subscribed and no read
/// runs.
pub fn poll_now(host host: Subject(Message)) -> Nil {
  process.send(host, PollNow)
}

/// The deadline of the read in flight, now: the read is ended as if its time had
/// come. Nothing happens when no read runs.
pub fn deadline_now(host host: Subject(Message)) -> Nil {
  process.send(host, DeadlineNow)
}

/// How many pages are subscribed, as of the poller's handling of everything sent
/// to it before this. Waits as long as the poller takes.
pub fn subscriber_count(host host: Subject(Message)) -> Int {
  process.call_forever(host, CountSubscribers)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Subscribe(subscriber:) -> actor.continue(subscribed(state, subscriber))
    Unsubscribe(subscriber:) ->
      actor.continue(left(
        state,
        subscribers.leave(state.subscribers, subscriber:),
      ))
    SubscriberDown(down:) ->
      actor.continue(left(
        state,
        subscribers.leave_ended(state.subscribers, monitor: down.monitor),
      ))
    Tick(chain:) -> actor.continue(ticked(state, chain))
    PollNow -> actor.continue(polled(state))
    ReadEnded(read:, result:) ->
      actor.continue(read_ended(state:, read:, result:))
    ReadDeadline(read:) ->
      case state.read {
        Some(Read(id:, ..)) if id == read ->
          actor.continue(deadline_passed(state))
        Some(_) | None -> actor.continue(state)
      }
    DeadlineNow -> actor.continue(deadline_passed(state))
    CountSubscribers(reply:) -> {
      process.send(reply, subscribers.count(state.subscribers))
      actor.continue(state)
    }
  }
}

/// A page subscribes: a new one is monitored, handed the latest reading, and
/// when it is the first starts the timer and a read, unless a read still runs.
fn subscribed(state: State, subscriber: Subject(Reading)) -> State {
  case subscribers.join(state.subscribers, subscriber:) {
    subscribers.AlreadyJoined -> state
    subscribers.LaterJoined(joined) -> {
      option.map(state.latest, process.send(subscriber, _))
      State(..state, subscribers: joined)
    }
    subscribers.FirstJoined(joined) -> {
      option.map(state.latest, process.send(subscriber, _))
      let state = State(..state, subscribers: joined)
      case state.read {
        Some(_) -> state
        None -> start_read(state)
      }
    }
  }
}

/// The last page to leave drops the latest reading; a read that runs is left to
/// end, with its deadline, so that a page that opens before it ends does not
/// start a second one; its answer is dropped.
fn left(state: State, left: subscribers.Left(Reading, Message)) -> State {
  case left {
    subscribers.StillSubscribed(remaining) ->
      State(..state, subscribers: remaining)
    subscribers.LastLeft(remaining) ->
      State(..state, subscribers: remaining, latest: None)
  }
}

/// The timer's tick: while a page is subscribed and the tick is of the
/// current chain, the next is armed and the poller polls.
fn ticked(state: State, chain: Int) -> State {
  case subscribers.next_tick(state.subscribers, chain:) {
    Ok(armed) -> polled(State(..state, subscribers: armed))
    Error(Nil) -> state
  }
}

/// Reads now when a page is subscribed and no read runs; while one runs,
/// shows a read that has run too long as the last facts stale.
fn polled(state: State) -> State {
  case subscribers.is_empty(state.subscribers), state.read {
    True, _ -> state
    False, None -> start_read(state)
    False, Some(_) -> {
      let now_ms = state.settings.now_ms()
      let reading = host_reading.after_read(state.latest, Waiting, now_ms)
      case reading == state.latest {
        True -> state
        False -> shown(state, reading)
      }
    }
  }
}

/// Starts a read, with the deadline timer that ends it.
fn start_read(state: State) -> State {
  let id = state.next_read
  let self = state.self
  state.settings.start_read(fn(result) {
    process.send(self, ReadEnded(read: id, result:))
  })
  let deadline =
    process.send_after(
      state.self,
      state.settings.deadline_ms,
      ReadDeadline(read: id),
    )
  State(..state, read: Some(Read(id:, deadline:)), next_read: id + 1)
}

/// A read ended: its answer makes the next reading, unless the read was given
/// up on (its deadline passed) or no page is subscribed, when the answer is
/// dropped.
fn read_ended(
  state state: State,
  read read: Int,
  result result: Result(script.Finished, script.Failure),
) -> State {
  case state.read {
    Some(Read(id:, deadline:)) if id == read -> {
      process.cancel_timer(deadline)
      end_read(State(..state, read: None), Ran(result))
    }
    Some(_) | None -> state
  }
}

/// The read in flight has run to its deadline.
fn deadline_passed(state: State) -> State {
  case state.read {
    None -> state
    Some(Read(deadline:, ..)) -> {
      process.cancel_timer(deadline)
      end_read(
        State(..state, read: None),
        Ran(Error(script.DeadlineReached(state.settings.deadline_ms))),
      )
    }
  }
}

fn end_read(state: State, outcome: host_reading.Outcome) -> State {
  use <- bool.guard(
    when: subscribers.is_empty(state.subscribers),
    return: state,
  )
  let reading =
    host_reading.after_read(state.latest, outcome, state.settings.now_ms())
  shown(state, reading)
}

/// Keeps the reading as the latest and sends it to every subscriber.
fn shown(state: State, reading: Option(Reading)) -> State {
  case reading {
    None -> state
    Some(reading) -> {
      list.each(subscribers.subjects(state.subscribers), process.send(
        _,
        reading,
      ))
      State(..state, latest: Some(reading))
    }
  }
}
