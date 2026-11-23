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
//// - The pages, their monitors, the timer chain and the read in flight are
////   `read_poll`'s: the first page to subscribe starts a read, a tick while a
////   read runs starts no second one, and a read that has not answered at the
////   deadline is shown as failed, its answer, if it comes, dropped.
//// - A page that subscribes is handed the lines at once, once a read has
////   answered; a page that has not been sent anything shows no lines yet.
//// - A read that failed sends the same lines with the reason; the tracking of the
////   last good read is kept, and the next tick tries again.
//// - The last page to leave drops the lines and the tracking, so the next page
////   reads the tail and is never handed old lines; a read that runs then is
////   dropped when it ends, and a page that subscribed meanwhile gets a fresh
////   read.
//// - A page that gets an update is sent the whole ring (`log_lines` numbers each
////   entry); a read that changed nothing sends nothing.
//// - The follower keeps no state a restart cannot rebuild: pages subscribe again
////   when their runtimes are rebuilt (the supervisor restarts both together).
////
//// A program a read started is ended by the read's own deadline for each call;
//// a read process that dies with its program running leaves that program to
//// run to the end of its call (Podman has no client timeout), as the
//// Overview's reads do.

import genesis_prime/dashboard/container_log.{type Read, type Tracking}
import genesis_prime/dashboard/follow.{type Followed, type Trouble, Followed}
import genesis_prime/dashboard/log_lines.{type Lines, type Source}
import genesis_prime/dashboard/read_poll.{type Poll}
import genesis_prime/dashboard/script
import genesis_prime/dashboard/subscribers
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

/// Starts one read with this tracking and gives its answer to the function it
/// is handed, from any process; it must not wait for the read.
pub type StartRead =
  fn(Tracking, fn(Result(Read, Trouble)) -> Nil) -> Nil

/// What the follower is told. Pages and tests send these through `read_poll`'s
/// functions.
pub type Message =
  read_poll.Message(Followed, Result(Read, Trouble))

/// What a follower follows and how: the container's log, how a read is started,
/// how often it reads and how long a read may run, the arm of that timer
/// (`subscribers.send_after`, or a test's own).
pub type Settings {
  Settings(
    source: Source,
    start_read: StartRead,
    interval_ms: Int,
    deadline_ms: Int,
    arm: subscribers.Arm(Message),
  )
}

type State {
  State(
    settings: Settings,
    path: String,
    poll: Poll(Followed, Result(Read, Trouble)),
    lines: Lines,
    tracking: Tracking,
    trouble: Option(Trouble),
    answered: Bool,
  )
}

/// The text of the call that shows a container's log, as the page names its
/// source.
fn path_of(container: String) -> String {
  "podman logs " <> container
}

/// A read: inspects the container, then reads its log as the container's id and
/// the tracking say, each call under `call_deadline_ms`. It waits for both calls.
fn read_container(
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

fn initial(settings: Settings) -> fn(Subject(Message)) -> State {
  fn(self) {
    let assert Ok(container) = container_log.container_name(settings.source)
      as "a container follower follows the log of a container"
    State(
      settings:,
      path: path_of(container),
      poll: read_poll.new(
        owner: self,
        interval_ms: settings.interval_ms,
        deadline_ms: settings.deadline_ms,
        arm: settings.arm,
      ),
      lines: log_lines.new(settings.source),
      tracking: container_log.unread,
      trouble: None,
      answered: False,
    )
  }
}

/// The follower as a child of a supervisor, registered under `name` so that a
/// restarted follower is reached by the same subject.
pub fn supervised(
  settings settings: Settings,
  name name: Name(Message),
) -> supervision.ChildSpecification(Subject(Message)) {
  read_poll.supervised(initial(settings), handle, name)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  let #(poll, happened) =
    read_poll.handle(state.poll, message, started_by(state))
  let state = State(..state, poll:)
  actor.continue(case happened {
    read_poll.PageJoined(subscriber:) -> {
      case state.answered {
        True -> process.send(subscriber, followed(state))
        False -> Nil
      }
      state
    }
    read_poll.PageLeft(last:) ->
      case last {
        True -> dropped(state)
        False -> state
      }
    read_poll.ReadAnswered(answer:) -> shown(state, answer)
    read_poll.ReadTimedOut ->
      shown(state, Error(container_log.timed_out(state.settings.deadline_ms)))
    read_poll.ReadBusy | read_poll.Nothing -> state
  })
}

/// How a read starts: with the tracking as it stands.
fn started_by(state: State) -> read_poll.Start(Result(Read, Trouble)) {
  fn(answer) { state.settings.start_read(state.tracking, answer) }
}

/// The last page left: the lines and the tracking are dropped, so the next page
/// reads the tail.
fn dropped(state: State) -> State {
  State(
    ..state,
    lines: log_lines.new(state.settings.source),
    tracking: container_log.unread,
    trouble: None,
    answered: False,
  )
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
    False -> list.each(read_poll.subjects(state.poll), process.send(_, after))
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
