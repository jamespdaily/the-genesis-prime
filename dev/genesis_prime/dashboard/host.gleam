//// The poller that reads the state script for the Overview: one process for the
//// whole dashboard, reading while at least one page is subscribed and never
//// otherwise. The pages, the timer chain and the read in flight are
//// `read_poll`'s; this module decides what a page is handed and what an answer
//// means.
////
//// ```text
//// page runtime ──subscribe──► poller ──start_read──► script runner (a process of its own)
////      ▲                        │  ▲                        │
////      └──── Reading ───────────┘  └──── read ended ────────┘
//// timer ──tick──► poller            timer ──deadline──► poller
//// ```
////
//// - A page that subscribes is handed the latest reading at once, when there is
////   one. When the last page leaves, the latest reading is dropped, so the next
////   page waits for a read and is never handed an old one.
//// - A tick while a read runs starts no second read; it only lets a read that
////   has run too long show the facts last read as stale (`host_reading`).
//// - A read that has not ended at the deadline is sent as stale with that
////   reason; its answer, if it comes, is dropped.
//// - The poller keeps no state a restart cannot rebuild: pages subscribe again
////   when their runtimes are rebuilt (the supervisor restarts both together).

import genesis_prime/dashboard/host_reading.{type Reading, Ran, Waiting}
import genesis_prime/dashboard/read_poll.{type Poll}
import genesis_prime/dashboard/script
import genesis_prime/dashboard/subscribers
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

/// What the poller is told. Pages and tests send these through `read_poll`'s
/// functions.
pub type Message =
  read_poll.Message(Reading, Result(script.Finished, script.Failure))

/// What the poller does and when.
///
/// `start_read` starts one read and gives its answer to the function it is
/// handed, from any process; it must not wait for the read. `now_ms` is the
/// clock the readings are stamped by. `arm` arms the interval timer
/// (`subscribers.send_after`, or a test's own).
pub type Settings {
  Settings(
    start_read: read_poll.Start(Result(script.Finished, script.Failure)),
    now_ms: fn() -> Int,
    interval_ms: Int,
    deadline_ms: Int,
    arm: subscribers.Arm(Message),
  )
}

type State {
  State(
    settings: Settings,
    poll: Poll(Reading, Result(script.Finished, script.Failure)),
    latest: Option(Reading),
  )
}

/// A read that runs the script at `path` in a process of its own, linked to
/// the caller, under the runner's deadline.
pub fn script_reader(
  path path: String,
  environment environment: List(#(String, String)),
  deadline_ms deadline_ms: Int,
) -> read_poll.Start(Result(script.Finished, script.Failure)) {
  fn(answer) {
    let _reader =
      process.spawn(fn() {
        answer(script.run(path:, environment:, deadline_ms:))
      })
    Nil
  }
}

fn initial(settings: Settings) -> fn(Subject(Message)) -> State {
  fn(self) {
    State(
      settings:,
      poll: read_poll.new(
        owner: self,
        interval_ms: settings.interval_ms,
        deadline_ms: settings.deadline_ms,
        arm: settings.arm,
      ),
      latest: None,
    )
  }
}

/// The poller as a child of a supervisor, registered under `name` so that a
/// restarted poller is reached by the same subject.
pub fn supervised(
  settings settings: Settings,
  name name: Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  read_poll.supervised(initial(settings), handle, name)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  let #(poll, happened) =
    read_poll.handle(state.poll, message, state.settings.start_read)
  let state = State(..state, poll:)
  actor.continue(case happened {
    read_poll.PageJoined(subscriber:) -> {
      option.map(state.latest, process.send(subscriber, _))
      state
    }
    read_poll.PageLeft(last: True) -> State(..state, latest: None)
    read_poll.PageLeft(last: False) | read_poll.Nothing -> state
    read_poll.ReadAnswered(answer:) -> shown(state, Ran(answer))
    read_poll.ReadTimedOut ->
      shown(
        state,
        Ran(Error(script.DeadlineReached(state.settings.deadline_ms))),
      )
    read_poll.ReadBusy -> stale_while_waiting(state)
  })
}

/// A tick while a read runs: a read that has run too long shows the last facts
/// as stale.
fn stale_while_waiting(state: State) -> State {
  let reading =
    host_reading.after_read(state.latest, Waiting, state.settings.now_ms())
  case reading == state.latest {
    True -> state
    False -> sent(state, reading)
  }
}

/// A read ended: its outcome makes the next reading.
fn shown(state: State, outcome: host_reading.Outcome) -> State {
  sent(
    state,
    host_reading.after_read(state.latest, outcome, state.settings.now_ms()),
  )
}

/// Keeps the reading as the latest and sends it to every subscriber.
fn sent(state: State, reading: Option(Reading)) -> State {
  case reading {
    None -> state
    Some(reading) -> {
      list.each(read_poll.subjects(state.poll), process.send(_, reading))
      State(..state, latest: Some(reading))
    }
  }
}
