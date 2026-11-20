//// The follower of one log file: one process for each followed file, reading
//// it while at least one page is subscribed and never otherwise.
////
//// ```text
//// page runtime ──subscribe──► follower ──reader(path, cursor)──► piece of the file
////      ▲                         │  ▲
////      └──── Followed ───────────┘  └── timer: tick (a read, then the next tick)
//// ```
////
//// - The first page to subscribe starts the interval timer and reads the file;
////   a page that subscribes later is handed the newest lines at once, with no
////   read. When the last page leaves, the timer stops and the lines are
////   dropped, so the next page reads the tail again and is never handed old
////   lines. A tick with no page subscribed reads nothing.
//// - A read gives the bytes the file gained since the cursor, at most
////   `read_limit_bytes` of them: a log that grew by more is read over the
////   next ticks, never in one go, and each read is one update. The first read
////   of a file, and the read of a file that was replaced, give its last
////   `read_limit_bytes` bytes and drop the line they begin inside, so a large
////   file is never read whole.
//// - The reader follows the file by its inode and size: an inode that is not
////   the cursor's is a replaced file (read from its start, after a mark); a
////   size below the cursor's offset is a file cut shorter (read from its
////   start, after a mark); a file that is gone is `NotThere` and is read from
////   its start when it returns, after a mark. A file rewritten in place to the
////   same size, or to a size past the cursor's offset, between two reads, is
////   not seen: the new bytes are taken as the old file's growth. A file
////   replaced between the reader's look at its inode and its read is read at
////   the old file's offsets, and the next read sees the new inode.
//// - A page that gets an update is sent the whole ring, so it can keep one
////   element for each line (`log_lines` numbers each entry). A read that
////   changed nothing sends nothing. A read that failed sends the same lines
////   with the reason; the cursor of the last good read is kept, and the next
////   tick tries again.
//// - A subscriber that ends is dropped by the follower's own monitor of it,
////   and the follower tells its watcher, if it has one.
//// - The reader runs in the follower's process and takes at most one read of
////   `read_limit_bytes` bytes; a file system that hangs holds the follower, and
////   with it the pages that wait for lines.
//// - The follower keeps no state a restart cannot rebuild: pages subscribe
////   again when their runtimes are rebuilt (the supervisor restarts both
////   together).

import genesis_prime/dashboard/log_lines.{
  type Entry, type Lines, type Mark, type Source, LogCutShorter, LogReplaced,
}
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
pub const read_limit_bytes = 262_144

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

/// Why a read gave nothing: the file is not there, or it cannot be read, with
/// the reason as the operating system names it.
pub type Trouble {
  NotThere
  Unreadable(reason: String)
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
/// it reads, and who is told of its reads and drops.
pub type Settings {
  Settings(
    source: Source,
    path: String,
    reader: Reader,
    interval_ms: Int,
    watcher: Option(Subject(Event)),
  )
}

/// What the follower is told. Pages and tests send these through this module's
/// functions.
pub opaque type Message {
  Subscribe(subscriber: Subject(Followed))
  Unsubscribe(subscriber: Subject(Followed))
  Tick
  ReadNow
  SubscriberDown(down: process.Down)
  CountSubscribers(reply: Subject(Int))
}

type Subscriber {
  Subscriber(subject: Subject(Followed), monitor: process.Monitor)
}

type State {
  State(
    self: Subject(Message),
    settings: Settings,
    subscribers: List(Subscriber),
    lines: Lines,
    cursor: Cursor,
    trouble: Option(Trouble),
    tick: Option(process.Timer),
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
    read_piece(path, fn(inode, size) { plan(cursor, inode, size) })
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
fn plan(cursor: Cursor, inode: Int, size: Int) -> #(Int, Int, Plan) {
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
      |> process.select_monitors(SubscriberDown)
    idle(State(
      self:,
      settings:,
      subscribers: [],
      lines: log_lines.new(settings.source),
      cursor: Unread,
      trouble: None,
      tick: None,
    ))
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
  process.send(follower, Subscribe(subscriber:))
}

/// Takes a page's subscription back.
pub fn unsubscribe(
  follower follower: Subject(Message),
  subscriber subscriber: Subject(Followed),
) -> Nil {
  process.send(follower, Unsubscribe(subscriber:))
}

/// A tick without the timer: reads now when a page is subscribed.
pub fn read_now(follower follower: Subject(Message)) -> Nil {
  process.send(follower, ReadNow)
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
      actor.continue(left(state, fn(entry) { entry.subject == subscriber }))
    SubscriberDown(down:) -> {
      let state = left(state, fn(entry) { entry.monitor == down.monitor })
      tell(state, SubscriberDropped(state.settings.source))
      actor.continue(state)
    }
    Tick ->
      case state.subscribers {
        [] -> actor.continue(State(..state, tick: None))
        [_, ..] -> actor.continue(state |> arm_tick |> read_and_send)
      }
    ReadNow -> actor.continue(read_and_send(state))
    CountSubscribers(reply:) -> {
      process.send(reply, list.length(state.subscribers))
      actor.continue(state)
    }
  }
}

/// A page subscribes: it is monitored, and when it is the first the timer
/// starts and the file is read. It is sent the newest lines at once.
fn subscribed(state: State, subscriber: Subject(Followed)) -> State {
  let already =
    list.any(state.subscribers, fn(entry) { entry.subject == subscriber })
  use <- bool.guard(when: already, return: state)
  let assert Ok(pid) = process.subject_owner(subscriber)
    as "a page's subject has an owner"
  let entry = Subscriber(subject: subscriber, monitor: process.monitor(pid))
  let first = state.subscribers == []
  let state = State(..state, subscribers: [entry, ..state.subscribers])
  let state = case first {
    True -> state |> arm_tick |> read
    False -> state
  }
  process.send(subscriber, followed(state))
  state
}

/// Drops the subscribers `leaves` picks; the last to leave stops the timer and
/// drops the lines.
fn left(state: State, leaves: fn(Subscriber) -> Bool) -> State {
  let #(gone, staying) = list.partition(state.subscribers, leaves)
  list.each(gone, fn(entry) { process.demonitor_process(entry.monitor) })
  let state = State(..state, subscribers: staying)
  case gone, staying {
    [], _ | _, [_, ..] -> state
    [_, ..], [] -> idle(state)
  }
}

/// Nobody is subscribed: no timer, no lines, and the file is unread, so the
/// next page reads its tail.
fn idle(state: State) -> State {
  option.map(state.tick, process.cancel_timer)
  State(
    ..state,
    tick: None,
    lines: log_lines.new(state.settings.source),
    cursor: Unread,
    trouble: None,
  )
}

fn arm_tick(state: State) -> State {
  let timer = process.send_after(state.self, state.settings.interval_ms, Tick)
  State(..state, tick: Some(timer))
}

fn tell(state: State, event: Event) -> Nil {
  option.map(state.settings.watcher, process.send(_, event))
  Nil
}

/// Reads when a page is subscribed, and sends every subscriber the lines when
/// the read changed them or the file's state.
fn read_and_send(state: State) -> State {
  case state.subscribers {
    [] -> state
    [_, ..] -> {
      let before = followed(state)
      let state = read(state)
      let after = followed(state)
      case after == before {
        True -> Nil
        False ->
          list.each(state.subscribers, fn(entry) {
            process.send(entry.subject, after)
          })
      }
      state
    }
  }
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
  tell(state, ReadMade(state.settings.source))
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
    Error(Unreadable(_) as trouble) -> State(..state, trouble: Some(trouble))
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
