//// The follower of one container's log: one process for each followed
//// container, reading it while at least one page is subscribed and never
//// otherwise. A read is two calls of `podman` that end (never `podman logs
//// --follow`, which a quiet container keeps alive after its reader is gone), so
//// every read gets an answer or a deadline, and a hung Podman shows as a
//// failed read.
////
//// ```text
//// page runtime ──subscribe──► follower ──start_read(tracking)──► reader (a process of its own)
////      ▲                         │  ▲                                │ inspect, then logs
////      └──── Followed ───────────┘  └──────── read ended ────────────┘
//// timer ──tick──► follower            timer ──deadline──► follower
//// ```
////
//// - The pages, their monitors and the one timer chain are `subscribers`'; a
////   tick with no page subscribed, or of an earlier chain, reads nothing.
//// - The first page to subscribe starts a read; a page that subscribes later is
////   handed the lines at once, once a read has answered. A page that has not been
////   sent anything shows no lines yet.
//// - A tick while a read runs starts no second read. A read that has not
////   answered at the deadline is shown as failed, and its answer, if it comes, is
////   dropped.
//// - A read that failed sends the same lines with the reason; the tracking of the
////   last good read is kept, and the next tick tries again.
//// - The last page to leave drops the lines and the tracking, so the next page
////   reads the tail and is never handed old lines. A read that runs then goes on
////   to its end and its answer is dropped; a page that subscribes before it ends
////   waits for it, and a fresh read starts when it has ended, so two reads never
////   run at once.
//// - A page that gets an update is sent the whole ring (`log_lines` numbers each
////   entry); a read that changed nothing sends nothing.
//// - A subscriber that ends is dropped by the follower's own monitor of it, and
////   the follower tells its watcher, if it has one.
//// - The follower keeps no state a restart cannot rebuild: pages subscribe again
////   when their runtimes are rebuilt (the supervisor restarts both together).
////
//// A program a read started is ended by the read's own deadline for each call;
//// a read process that dies with its program running leaves that program to
//// run to the end of its call (Podman has no client timeout), as the
//// Overview's reads do.

import genesis_prime/dashboard/container_log.{type Read, type Tracking}
import genesis_prime/dashboard/follow.{
  type Event, type Followed, type Trouble, Followed, ReadMade, SubscriberDropped,
}
import genesis_prime/dashboard/log_lines.{type Lines, type Source}
import genesis_prime/dashboard/script
import genesis_prime/dashboard/subscribers.{type Subscribers}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result

/// How often a follower reads while a page is subscribed: 2 s, a guess (a read
/// of both calls takes 0.3 s, measured, and a line may show up to that much
/// later).
pub const interval_ms = 2000

/// How long one call of `podman` may run before it is ended: 5 s, a guess (a
/// call takes 0.12 to 0.17 s, measured).
pub const call_deadline_ms = 5000

/// How long a follower waits for the read's calls before it shows the read as
/// failed, for calls with this deadline: both calls and the ending of one.
pub fn read_deadline_ms(call_deadline_ms call_deadline_ms: Int) -> Int {
  3 * call_deadline_ms
}

/// How long the supervisor waits for a follower to stop.
const shutdown_ms = 1000

/// How long the start waits for a follower's initialiser.
const initialiser_ms = 1000

/// Starts one read with this tracking and gives its answer to the function it
/// is handed, from any process; it must not wait for the read.
pub type StartRead =
  fn(Tracking, fn(Result(Read, Trouble)) -> Nil) -> Nil

/// What a follower follows and how: the container's log, how a read is started,
/// how often it reads and how long a read may run, the arm of that timer
/// (`subscribers.send_after`, or a test's own), and who is told of its reads and
/// drops.
pub type Settings {
  Settings(
    source: Source,
    start_read: StartRead,
    interval_ms: Int,
    deadline_ms: Int,
    arm: subscribers.Arm(Message),
    watcher: Option(Subject(Event)),
  )
}

/// What the follower is told. Pages and tests send these through this module's
/// functions.
pub opaque type Message {
  Subscribe(subscriber: Subject(Followed))
  Unsubscribe(subscriber: Subject(Followed))
  Tick(chain: Int)
  ReadNow
  SubscriberDown(down: process.Down)
  ReadEnded(read: Int, result: Result(Read, Trouble))
  ReadDeadline(read: Int)
  DeadlineNow
  CountSubscribers(reply: Subject(Int))
}

/// The read in flight, the timer of its deadline, and whether its answer is
/// wanted: it is not when the last page left after it started.
type Running {
  Running(id: Int, deadline: process.Timer, wanted: Bool)
}

type State {
  State(
    self: Subject(Message),
    settings: Settings,
    path: String,
    subscribers: Subscribers(Followed, Message),
    lines: Lines,
    tracking: Tracking,
    trouble: Option(Trouble),
    answered: Bool,
    running: Option(Running),
    next_read: Int,
  )
}

/// The text of the call that shows a container's log, as the page names its
/// source.
fn path_of(container: String) -> String {
  "podman logs " <> container
}

/// A read: inspects the container, then reads its log as the container's id and
/// the tracking say, each call under `call_deadline_ms`. It waits for both calls.
pub fn read_container(
  podman podman: String,
  container container: String,
  call_deadline_ms call_deadline_ms: Int,
  tracking tracking: Tracking,
) -> Result(Read, Trouble) {
  use id <- result.try(
    container_log.container_id(script.run_with(
      path: podman,
      arguments: ["container", "inspect", "--format", "{{.Id}}", container],
      environment: [],
      deadline_ms: call_deadline_ms,
    )),
  )
  let plan = container_log.plan(tracking:, container:, id:)
  use output <- result.map(
    container_log.log_output(script.run_with(
      path: podman,
      arguments: plan.arguments,
      environment: [],
      deadline_ms: call_deadline_ms,
    )),
  )
  container_log.read(plan:, output:)
}

/// Reads that run `read_container` in a process of their own, linked to the
/// caller.
pub fn podman_reader(
  podman podman: String,
  container container: String,
  call_deadline_ms call_deadline_ms: Int,
) -> StartRead {
  fn(tracking, answer) {
    let _reader =
      process.spawn(fn() {
        answer(read_container(podman:, container:, call_deadline_ms:, tracking:))
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
    let assert Ok(container) = container_log.container_name(settings.source)
      as "a container follower follows the log of a container"
    State(
      self:,
      settings:,
      path: path_of(container),
      subscribers: subscribers.new(
        owner: self,
        interval_ms: settings.interval_ms,
        arm: settings.arm,
        tick: Tick,
      ),
      lines: log_lines.new(settings.source),
      tracking: container_log.unread,
      trouble: None,
      answered: False,
      running: None,
      next_read: 0,
    )
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
}

/// Starts a follower linked to the caller.
pub fn start(
  settings settings: Settings,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.start(builder(settings))
}

/// The follower as a child of a supervisor, registered under `name` so that a
/// restarted follower is reached by the same subject.
pub fn supervised(
  settings settings: Settings,
  name name: Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { actor.start(actor.named(builder(settings), name)) })
  |> supervision.timeout(shutdown_ms)
}

/// Subscribes a page: it is sent the lines once a read has answered, and an
/// update each time a read changes them.
pub fn subscribe(
  follower follower: Subject(Message),
  subscriber subscriber: Subject(Followed),
) -> Nil {
  process.send(follower, Subscribe(subscriber:))
}

/// Takes a page's subscription back.
pub fn unsubscribe(
  follower follower: Subject(Message),
  subscriber subscriber: Subject(Followed),
) -> Nil {
  process.send(follower, Unsubscribe(subscriber:))
}

/// A tick without the timer: reads now when a page is subscribed and no read
/// runs.
pub fn read_now(follower follower: Subject(Message)) -> Nil {
  process.send(follower, ReadNow)
}

/// The deadline of the read in flight, now: the read is shown as failed as if
/// its time had come. Nothing happens when no read runs.
pub fn deadline_now(follower follower: Subject(Message)) -> Nil {
  process.send(follower, DeadlineNow)
}

/// How many pages are subscribed, as of the follower's handling of everything
/// sent to it before this. Waits as long as the follower takes.
pub fn subscriber_count(follower follower: Subject(Message)) -> Int {
  process.call_forever(follower, CountSubscribers)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Subscribe(subscriber:) -> actor.continue(subscribed(state, subscriber))
    Unsubscribe(subscriber:) ->
      actor.continue(left(
        state,
        subscribers.leave(state.subscribers, subscriber:),
      ))
    SubscriberDown(down:) -> {
      let state =
        left(
          state,
          subscribers.leave_ended(state.subscribers, monitor: down.monitor),
        )
      tell(state, SubscriberDropped(state.settings.source))
      actor.continue(state)
    }
    Tick(chain:) ->
      case subscribers.next_tick(state.subscribers, chain:) {
        Ok(armed) -> actor.continue(polled(State(..state, subscribers: armed)))
        Error(Nil) -> actor.continue(state)
      }
    ReadNow -> actor.continue(polled(state))
    ReadEnded(read:, result:) ->
      actor.continue(read_ended(state:, read:, result:))
    ReadDeadline(read:) ->
      case state.running {
        Some(Running(id:, ..)) if id == read ->
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

/// A page subscribes: it is monitored and handed the lines when a read has
/// answered, and when it is the first the timer starts and a read, unless one
/// still runs.
fn subscribed(state: State, subscriber: Subject(Followed)) -> State {
  case subscribers.join(state.subscribers, subscriber:) {
    subscribers.AlreadyJoined -> state
    subscribers.LaterJoined(joined) -> {
      let state = State(..state, subscribers: joined)
      case state.answered {
        True -> process.send(subscriber, followed(state))
        False -> Nil
      }
      state
    }
    subscribers.FirstJoined(joined) -> {
      let state = State(..state, subscribers: joined)
      case state.running {
        Some(_) -> state
        None -> start_read(state)
      }
    }
  }
}

/// The last page to leave drops the lines and the tracking, and tells a read
/// that runs that its answer is not wanted.
fn left(state: State, left: subscribers.Left(Followed, Message)) -> State {
  case left {
    subscribers.StillSubscribed(remaining) ->
      State(..state, subscribers: remaining)
    subscribers.LastLeft(remaining) ->
      State(
        ..state,
        subscribers: remaining,
        lines: log_lines.new(state.settings.source),
        tracking: container_log.unread,
        trouble: None,
        answered: False,
        running: option.map(state.running, fn(running) {
          Running(..running, wanted: False)
        }),
      )
  }
}

fn tell(state: State, event: Event) -> Nil {
  option.map(state.settings.watcher, process.send(_, event))
  Nil
}

/// Starts a read when a page is subscribed and no read runs.
fn polled(state: State) -> State {
  case subscribers.is_empty(state.subscribers), state.running {
    True, _ | False, Some(_) -> state
    False, None -> start_read(state)
  }
}

/// Starts a read with the tracking, and the timer of its deadline.
fn start_read(state: State) -> State {
  tell(state, ReadMade(state.settings.source))
  let id = state.next_read
  let self = state.self
  state.settings.start_read(state.tracking, fn(result) {
    process.send(self, ReadEnded(read: id, result:))
  })
  let deadline =
    process.send_after(
      state.self,
      state.settings.deadline_ms,
      ReadDeadline(read: id),
    )
  State(
    ..state,
    running: Some(Running(id:, deadline:, wanted: True)),
    next_read: id + 1,
  )
}

/// A read answered: its answer is taken when it is wanted, and dropped when
/// the deadline has passed it (it is no longer the read in flight) or the last
/// page left after it started.
fn read_ended(
  state state: State,
  read read: Int,
  result result: Result(Read, Trouble),
) -> State {
  case state.running {
    Some(Running(id:, deadline:, wanted:)) if id == read -> {
      process.cancel_timer(deadline)
      ended(state: State(..state, running: None), wanted:, outcome: result)
    }
    Some(_) | None -> state
  }
}

/// The read in flight has run to its deadline.
fn deadline_passed(state: State) -> State {
  case state.running {
    None -> state
    Some(Running(deadline:, wanted:, ..)) -> {
      process.cancel_timer(deadline)
      ended(
        state: State(..state, running: None),
        wanted:,
        outcome: Error(container_log.timed_out(state.settings.deadline_ms)),
      )
    }
  }
}

/// A read ended: what it gave is taken and sent when it is wanted; a read that
/// is not wanted is dropped, and a page that subscribed meanwhile gets a fresh
/// read.
fn ended(
  state state: State,
  wanted wanted: Bool,
  outcome outcome: Result(Read, Trouble),
) -> State {
  case wanted {
    True -> shown(state, outcome)
    False -> polled(state)
  }
}

/// Takes what a read gave and sends every subscriber the lines when it changed
/// them, or when it is the first answer.
fn shown(state: State, result: Result(Read, Trouble)) -> State {
  let before = case state.answered {
    True -> Some(followed(state))
    False -> None
  }
  let state = case result {
    Ok(read) ->
      State(
        ..state,
        lines: lines_after(state.lines, read),
        tracking: read.tracking,
        trouble: None,
        answered: True,
      )
    Error(trouble) -> State(..state, trouble: Some(trouble), answered: True)
  }
  let after = followed(state)
  case before == Some(after) {
    True -> Nil
    False ->
      list.each(subscribers.subjects(state.subscribers), process.send(_, after))
  }
  state
}

/// The lines after a read: its mark, then its new lines.
fn lines_after(lines: Lines, read: Read) -> Lines {
  let lines = case read.mark {
    Some(mark) -> log_lines.mark(lines, mark)
    None -> lines
  }
  log_lines.feed(lines, read.bytes)
}

fn followed(state: State) -> Followed {
  Followed(
    source: state.settings.source,
    path: state.path,
    trouble: state.trouble,
    entries: log_lines.entries(state.lines),
  )
}
