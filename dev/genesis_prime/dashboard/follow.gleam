//// The follower of one log file: one process for each followed file, reading
//// it while at least one page is subscribed and never otherwise.
////
//// ```text
//// page runtime ──subscribe──► follower ──reader(path, cursor)──► piece of the file
////      ▲                         │  ▲
////      └──── Followed ───────────┘  └── timer: tick (a read, then the next tick)
//// ```
////
//// - The pages, their monitors and the one timer chain are `subscribers`'; a
////   tick with no page subscribed, or of an earlier chain, reads nothing.
//// - The first page to subscribe reads the file; a later page is handed the
////   newest lines at once, with no read.
//// - The last page to leave drops the lines, so the next page reads the tail
////   and is never handed old lines.
//// - A read gives the bytes the file gained since the cursor, at most
////   `read_limit_bytes`; a log that grew by more is read over the next ticks.
//// - The first read of a file, and the read of a replaced file, give its last
////   `read_limit_bytes` bytes without the line they begin inside.
//// - The reader follows the file by the inode and size of the file it opened:
////   another inode is a replaced file, a size below the cursor's offset is a cut
////   file, each read from its start after a mark; a file that is gone is
////   `NotThere` and is read from its start when it returns, after a mark.
//// - A file rewritten in place to the same size, or to a size past the cursor's
////   offset, between two reads is not seen: its new bytes are taken as growth.
//// - A page that gets an update is sent the whole ring, so it can keep one
////   element for each line (`log_lines` numbers each entry); a read that
////   changed nothing sends nothing.
//// - A read that failed sends the same lines with the reason; the cursor of the
////   last good read is kept, and the next tick tries again.
//// - A subscriber that ends is dropped by the follower's own monitor of it, and
////   the follower tells its watcher, if it has one.
//// - The reader runs in the follower's process, one read of at most
////   `read_limit_bytes`; a file system that hangs holds the follower, and with
////   it the pages that wait for lines.
//// - The follower keeps no state a restart cannot rebuild: pages subscribe again
////   when their runtimes are rebuilt (the supervisor restarts both together).

import genesis_prime/dashboard/log_lines.{
  type Entry, type Lines, type Mark, type Source, LogCutShorter, LogReplaced,
}
import genesis_prime/dashboard/subscribers.{type Subscribers}
import gleam/bit_array
import gleam/bool
import gleam/erlang/process.{type Name, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result

/// How often a follower reads while a page is subscribed: 1 s, a guess (the
/// busiest hour of a real log held 62 lines).
pub const interval_ms = 1000

/// How many bytes one read gives at most, the first read of a file included:
/// 256 KiB, a guess (a real log is 0.3 MB in 15 days, and the page keeps 500
/// lines).
const read_limit_bytes = 262_144

/// How long the supervisor waits for a follower to stop.
const shutdown_ms = 1000

/// How long the start waits for a follower's initialiser.
const initialiser_ms = 1000

/// Where the reader stands in a file: not yet read, the file gone since the
/// last read, or the file's inode and the offset up to which it was read.
pub type Cursor {
  Unread
  Gone
  At(inode: Int, offset: Int)
}

/// What a read gave: the cursor to read from next, the bytes, the change of
/// the file that came before them, and whether the bytes begin inside a line.
pub type Fetched {
  Fetched(
    cursor: Cursor,
    bytes: BitArray,
    mark: Option(Mark),
    starts_inside_a_line: Bool,
  )
}

/// Why a read gave nothing: the file or the container is not there, it cannot be
/// read, with the reason as the operating system names it, or Podman cannot be
/// reached (a container's log only), with the words it said.
pub type Trouble {
  NotThere
  Unreadable(reason: String)
  PodmanUnreachable(reason: String)
}

/// A read: the path and the cursor in, what the file gave, or why not.
pub type Reader =
  fn(String, Cursor) -> Result(Fetched, Trouble)

/// What a subscriber is sent: the log, its file, whether the file could be read
/// at the last read, and the ring of entries, the oldest first.
pub type Followed {
  Followed(
    source: Source,
    path: String,
    trouble: Option(Trouble),
    entries: List(Entry),
  )
}

/// What a follower tells its watcher: a read was made, or a subscriber that had
/// ended was dropped.
pub type Event {
  ReadMade(source: Source)
  SubscriberDropped(source: Source)
}

/// What a follower follows and how: the log, its file, the reader, how often
/// it reads and the arm of that timer (`subscribers.send_after`, or a test's
/// own), and who is told of its reads and drops.
pub type Settings {
  Settings(
    source: Source,
    path: String,
    reader: Reader,
    interval_ms: Int,
    arm: subscribers.Arm(Message),
    watcher: Option(Subject(Event)),
  )
}

/// What the follower is told. Pages and tests send these through this module's
/// functions.
pub opaque type Message {
  Pages(request: subscribers.Request(Followed))
  Tick(chain: Int)
  ReadNow
}

type State {
  State(
    self: Subject(Message),
    settings: Settings,
    subscribers: Subscribers(Followed, Message),
    lines: Lines,
    cursor: Cursor,
    trouble: Option(Trouble),
  )
}

/// Where the next read starts and what it is told about the file: the file's
/// inode, the offset and length to read, the change of the file, and whether
/// the read begins inside a line.
type Plan {
  Plan(inode: Int, offset: Int, mark: Option(Mark), starts_inside_a_line: Bool)
}

@external(erlang, "dashboard_follow_ffi", "read_piece")
fn read_piece(
  path: String,
  decide: fn(Int, Int) -> #(Int, Int, Plan),
) -> Result(#(Plan, BitArray), Trouble)

/// The real reader: opens the file, reads the piece the cursor and the file's
/// own inode and size call for, and closes it.
pub fn file_reader() -> Reader {
  fn(path, cursor) {
    read_piece(path, fn(inode, size) { plan(cursor:, inode:, size:) })
    |> result.map(fn(read) {
      let #(plan, bytes) = read
      Fetched(
        cursor: At(
          inode: plan.inode,
          offset: plan.offset + bit_array.byte_size(bytes),
        ),
        bytes:,
        mark: plan.mark,
        starts_inside_a_line: plan.starts_inside_a_line,
      )
    })
  }
}

/// What to read of a file with this inode and size, from this cursor.
fn plan(
  cursor cursor: Cursor,
  inode inode: Int,
  size size: Int,
) -> #(Int, Int, Plan) {
  case cursor {
    At(inode: seen, offset:) if seen == inode && size >= offset -> {
      let length = int.min(read_limit_bytes, size - offset)
      #(
        offset,
        length,
        Plan(inode:, offset:, mark: None, starts_inside_a_line: False),
      )
    }
    At(inode: seen, ..) if seen == inode ->
      from_the_end(inode:, size:, mark: Some(LogCutShorter))
    At(..) | Gone -> from_the_end(inode:, size:, mark: Some(LogReplaced))
    Unread -> from_the_end(inode:, size:, mark: None)
  }
}

/// The last `read_limit_bytes` bytes of the file, or all of it when it is
/// smaller.
fn from_the_end(
  inode inode: Int,
  size size: Int,
  mark mark: Option(Mark),
) -> #(Int, Int, Plan) {
  let offset = int.max(0, size - read_limit_bytes)
  #(
    offset,
    size - offset,
    Plan(inode:, offset:, mark:, starts_inside_a_line: offset > 0),
  )
}

fn builder(
  settings: Settings,
) -> actor.Builder(State, Message, Subject(Message)) {
  actor.new_with_initialiser(initialiser_ms, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> subscribers.select_ended(Pages)
    State(
      self:,
      settings:,
      subscribers: subscribers.new(
        owner: self,
        interval_ms: settings.interval_ms,
        arm: settings.arm,
        tick: Tick,
      ),
      lines: log_lines.new(settings.source),
      cursor: Unread,
      trouble: None,
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

/// Subscribes a page: it is sent the newest lines at once, and an update each
/// time a read changes them.
pub fn subscribe(
  follower follower: Subject(Message),
  subscriber subscriber: Subject(Followed),
) -> Nil {
  process.send(follower, Pages(subscribers.Join(subscriber:)))
}

/// A tick without the timer: reads now when a page is subscribed.
pub fn read_now(follower follower: Subject(Message)) -> Nil {
  process.send(follower, ReadNow)
}

/// How many pages are subscribed, as of the follower's handling of everything
/// sent to it before this. Waits as long as the follower takes.
pub fn subscriber_count(follower follower: Subject(Message)) -> Int {
  process.call_forever(follower, fn(reply) { Pages(subscribers.Count(reply:)) })
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Pages(request:) -> {
      let #(pages, handled) = subscribers.handle(state.subscribers, request)
      actor.continue(paged(State(..state, subscribers: pages), handled))
    }
    Tick(chain:) ->
      case subscribers.next_tick(state.subscribers, chain:) {
        Ok(armed) ->
          actor.continue(read_and_send(State(..state, subscribers: armed)))
        Error(Nil) -> actor.continue(state)
      }
    ReadNow -> actor.continue(read_and_send(state))
  }
}

/// What a page's request did: a page that joined is sent the newest lines at
/// once, and the first one reads the file first; the last page to leave drops
/// the lines and unreads the file, so the next page reads its tail; a page that
/// ended is told to the watcher.
fn paged(state: State, handled: subscribers.Handled(Followed)) -> State {
  case handled {
    subscribers.Unchanged -> state
    subscribers.PageJoined(subscriber:, first:) -> {
      let state = case first {
        True -> read(state)
        False -> state
      }
      process.send(subscriber, followed(state))
      state
    }
    subscribers.PageLeft(last:) -> {
      let state = case last {
        True ->
          State(
            ..state,
            lines: log_lines.new(state.settings.source),
            cursor: Unread,
            trouble: None,
          )
        False -> state
      }
      tell(
        watcher: state.settings.watcher,
        event: SubscriberDropped(state.settings.source),
      )
      state
    }
  }
}

/// Tells the watcher of a follower, if it has one.
pub fn tell(
  watcher watcher: Option(Subject(Event)),
  event event: Event,
) -> Nil {
  option.map(watcher, process.send(_, event))
  Nil
}

/// Reads when a page is subscribed, and sends every subscriber the lines when
/// the read changed them or the file's state.
fn read_and_send(state: State) -> State {
  use <- bool.guard(
    when: subscribers.is_empty(state.subscribers),
    return: state,
  )
  let before = followed(state)
  let state = read(state)
  let after = followed(state)
  case after == before {
    True -> Nil
    False ->
      list.each(subscribers.subjects(state.subscribers), process.send(_, after))
  }
  state
}

fn followed(state: State) -> Followed {
  Followed(
    source: state.settings.source,
    path: state.settings.path,
    trouble: state.trouble,
    entries: log_lines.entries(state.lines),
  )
}

/// One read of the file: its bytes go to the lines, after the change of the
/// file the reader saw; a failed read keeps the lines and the cursor.
fn read(state: State) -> State {
  tell(watcher: state.settings.watcher, event: ReadMade(state.settings.source))
  case state.settings.reader(state.settings.path, state.cursor) {
    Ok(fetched) -> {
      let lines = case fetched.mark {
        Some(mark) -> log_lines.mark(state.lines, mark)
        None -> state.lines
      }
      let lines = case fetched.starts_inside_a_line {
        True -> log_lines.start_inside_a_line(lines)
        False -> lines
      }
      State(
        ..state,
        lines: log_lines.feed(lines, fetched.bytes),
        cursor: fetched.cursor,
        trouble: None,
      )
    }
    Error(NotThere) ->
      State(..state, cursor: after_gone(state.cursor), trouble: Some(NotThere))
    Error(Unreadable(_) as trouble) | Error(PodmanUnreachable(_) as trouble) ->
      State(..state, trouble: Some(trouble))
  }
}

/// A file that was read and is gone is read from its start when it returns; one
/// that was never read stays unread.
fn after_gone(cursor: Cursor) -> Cursor {
  case cursor {
    Unread -> Unread
    At(..) | Gone -> Gone
  }
}
