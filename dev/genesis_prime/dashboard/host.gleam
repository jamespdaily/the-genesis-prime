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
//// - A tick while a read runs starts no second read; it only lets a read that
////   has run too long show the facts last read as stale (`host_reading`).
//// - A read that has not ended at the deadline is sent as stale with that
////   reason; its answer, if it comes, is dropped.
//// - A page that ends is dropped by the poller's own monitor of its runtime.
//// - The poller keeps no state a restart cannot rebuild: pages subscribe again
////   when their runtimes are rebuilt (the supervisor restarts both together).

import genesis_prime/dashboard/host_reading.{type Reading, Ran, Waiting}
import genesis_prime/dashboard/script
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
  Tick
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
/// clock the readings are stamped by.
pub type Settings {
  Settings(
    start_read: fn(fn(Result(script.Finished, script.Failure)) -> Nil) -> Nil,
    now_ms: fn() -> Int,
    interval_ms: Int,
    deadline_ms: Int,
  )
}

type Subscriber {
  Subscriber(subject: Subject(Reading), monitor: process.Monitor)
}

/// The read in flight and the timer of its deadline.
type Read {
  Read(id: Int, deadline: process.Timer)
}

type State {
  State(
    self: Subject(Message),
    settings: Settings,
    subscribers: List(Subscriber),
    latest: Option(Reading),
    read: Option(Read),
    tick: Option(process.Timer),
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
      subscribers: [],
      latest: None,
      read: None,
      tick: None,
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
      actor.continue(left(state, fn(entry) { entry.subject == subscriber }))
    SubscriberDown(down:) ->
      actor.continue(left(state, fn(entry) { entry.monitor == down.monitor }))
    Tick -> actor.continue(ticked(state))
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
      process.send(reply, list.length(state.subscribers))
      actor.continue(state)
    }
  }
}

/// A page subscribes: a new one is monitored, handed the latest reading, and
/// when it is the first starts the timer and a read, unless a read still runs.
fn subscribed(state: State, subscriber: Subject(Reading)) -> State {
  let already =
    list.any(state.subscribers, fn(entry) { entry.subject == subscriber })
  use <- bool.guard(when: already, return: state)
  let assert Ok(pid) = process.subject_owner(subscriber)
    as "a page's subject has an owner"
  let entry = Subscriber(subject: subscriber, monitor: process.monitor(pid))
  option.map(state.latest, process.send(subscriber, _))
  let first = state.subscribers == []
  let state = State(..state, subscribers: [entry, ..state.subscribers])
  use <- bool.guard(when: !first, return: state)
  let state = arm_tick(state)
  case state.read {
    Some(_) -> state
    None -> start_read(state)
  }
}

/// Drops the subscribers `leaves` picks; the last to leave stops the timer and
/// drops the latest reading, and leaves a read that runs to end.
fn left(state: State, leaves: fn(Subscriber) -> Bool) -> State {
  let #(gone, staying) = list.partition(state.subscribers, leaves)
  list.each(gone, fn(entry) { process.demonitor_process(entry.monitor) })
  let state = State(..state, subscribers: staying)
  case gone, staying {
    [], _ | _, [_, ..] -> state
    [_, ..], [] -> idle(state)
  }
}

/// Nobody is subscribed: no timer and no latest reading. A read in flight stays,
/// with its deadline, so that a page that opens before it ends does not start a
/// second one; its answer is dropped.
fn idle(state: State) -> State {
  option.map(state.tick, process.cancel_timer)
  State(..state, tick: None, latest: None)
}

fn arm_tick(state: State) -> State {
  let timer = process.send_after(state.self, state.settings.interval_ms, Tick)
  State(..state, tick: Some(timer))
}

/// The timer's tick: arms the next while a page is subscribed, then polls.
fn ticked(state: State) -> State {
  case state.subscribers {
    [] -> State(..state, tick: None)
    [_, ..] -> state |> arm_tick |> polled
  }
}

/// Reads now when a page is subscribed and no read runs; while one runs,
/// shows a read that has run too long as the last facts stale.
fn polled(state: State) -> State {
  case state.subscribers, state.read {
    [], _ -> state
    [_, ..], None -> start_read(state)
    [_, ..], Some(_) -> {
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
  case state.subscribers {
    [] -> state
    [_, ..] -> {
      let reading =
        host_reading.after_read(state.latest, outcome, state.settings.now_ms())
      shown(state, reading)
    }
  }
}

/// Keeps the reading as the latest and sends it to every subscriber.
fn shown(state: State, reading: Option(Reading)) -> State {
  case reading {
    None -> state
    Some(reading) -> {
      list.each(state.subscribers, fn(entry) {
        process.send(entry.subject, reading)
      })
      State(..state, latest: Some(reading))
    }
  }
}
