//// The shell that the dashboard's asynchronous readers share: a process that
//// reads while at least one page is subscribed and never otherwise, with one
//// read in flight at a time. The Overview's poller (`host`) and each container
//// follower (`container_follow`) are built on it and decide only what a page
//// is handed and what an answer means.
////
//// ```text
//// page runtime ──Join/Leave──► process ──start──► reader (a process of its own)
////      ▲                         │  ▲                       │
////      └──── what it shows ──────┘  └──── ReadEnded(id) ────┘
//// timer ──Tick(chain)──► process      timer ──ReadDeadline(id)──► process
//// ```
////
//// - The pages, their monitors and the one timer chain are `subscribers`'.
//// - The first page to join starts a read, unless one runs; a tick, or a read
////   asked for by a test, starts one when a page is subscribed and none runs.
////   A tick while a read runs starts no second read and is reported as
////   `ReadBusy`.
//// - A read is ended by its answer or by its deadline, whichever comes first;
////   the other is then dropped (a deadline timer carries the read's number, and
////   an answer of a read that is no longer the one in flight is refused).
//// - The last page to leave makes the read in flight unwanted: its answer, or
////   its deadline, ends it and shows nothing, whoever has joined since. When a
////   page is subscribed by then, the next read starts at once; two reads never
////   run at once.

import genesis_prime/dashboard/subscribers.{type Subscribers}
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision

/// How long a start waits for the process's initialiser.
const initialiser_ms = 1000

/// How long the supervisor waits for a process to stop.
const shutdown_ms = 1000

/// What the process is told, and `answer` is what a read gives. Pages and tests
/// send these through this module's functions.
pub opaque type Message(item, answer) {
  Pages(request: subscribers.Request(item))
  Tick(chain: Int)
  ReadNow
  ReadEnded(read: Int, answer: answer)
  ReadDeadline(read: Int)
  DeadlineNow
}

/// The read in flight, the timer of its deadline, and whether its answer is
/// wanted: it is not when the last page left after it started.
type Running {
  Running(id: Int, deadline: process.Timer, wanted: Bool)
}

/// The pages of one process and its read in flight.
pub opaque type Poll(item, answer) {
  Poll(
    owner: Subject(Message(item, answer)),
    deadline_ms: Int,
    subscribers: Subscribers(item, Message(item, answer)),
    running: Option(Running),
    next_read: Int,
  )
}

/// What a message did, for the process to act on.
pub type Happened(item, answer) {
  /// A page joined, the first or a later one; it is to be handed what the
  /// process has to show.
  PageJoined(subscriber: Subject(item))
  /// A page left (`last`: the last one, so the process drops what it shows) or
  /// ended (`ended`: it did not ask to leave).
  PageLeft(last: Bool, ended: Bool)
  /// The read in flight answered and its answer is wanted.
  ReadAnswered(answer: answer)
  /// The read in flight passed its deadline and its answer would have been
  /// wanted.
  ReadTimedOut
  /// A tick, or a read asked for, came while a read runs.
  ReadBusy
  /// Nothing for the process to do.
  Nothing
}

/// Starts one read and gives its answer to the function it is handed, from any
/// process; it must not wait for the read.
pub type Start(answer) =
  fn(fn(answer) -> Nil) -> Nil

/// No page and no read. `interval_ms` and `arm` are the timer chain's
/// (`subscribers.send_after`, or a test's own); a read that has not ended after
/// `deadline_ms` is reported as `ReadTimedOut`.
pub fn new(
  owner owner: Subject(Message(item, answer)),
  interval_ms interval_ms: Int,
  deadline_ms deadline_ms: Int,
  arm arm: subscribers.Arm(Message(item, answer)),
) -> Poll(item, answer) {
  Poll(
    owner:,
    deadline_ms:,
    subscribers: subscribers.new(owner:, interval_ms:, arm:, tick: Tick),
    running: None,
    next_read: 0,
  )
}

/// The subjects of the pages that are subscribed, the newest first.
pub fn subjects(poll: Poll(item, answer)) -> List(Subject(item)) {
  subscribers.subjects(poll.subscribers)
}

/// Does what a message says. `start` starts the read when one is to start; it
/// is built from the process's state as it stands before this message.
pub fn handle(
  poll poll: Poll(item, answer),
  message message: Message(item, answer),
  start start: Start(answer),
) -> #(Poll(item, answer), Happened(item, answer)) {
  case message {
    Pages(request:) -> paged(poll:, request:, start:)
    Tick(chain:) ->
      case subscribers.next_tick(poll.subscribers, chain:) {
        Ok(armed) -> polled(Poll(..poll, subscribers: armed), start)
        Error(Nil) -> #(poll, Nothing)
      }
    ReadNow -> polled(poll, start)
    ReadEnded(read:, answer:) ->
      case poll.running {
        Some(Running(id:, ..)) if id == read ->
          ended(poll:, start:, how: ReadAnswered(answer))
        Some(_) | None -> #(poll, Nothing)
      }
    ReadDeadline(read:) ->
      case poll.running {
        Some(Running(id:, ..)) if id == read ->
          ended(poll:, start:, how: ReadTimedOut)
        Some(_) | None -> #(poll, Nothing)
      }
    DeadlineNow -> ended(poll:, start:, how: ReadTimedOut)
  }
}

fn paged(
  poll poll: Poll(item, answer),
  request request: subscribers.Request(item),
  start start: Start(answer),
) -> #(Poll(item, answer), Happened(item, answer)) {
  let #(pages, handled) = subscribers.handle(poll.subscribers, request)
  let poll = Poll(..poll, subscribers: pages)
  case handled {
    subscribers.Unchanged -> #(poll, Nothing)
    subscribers.PageJoined(subscriber:, first:) -> {
      let poll = case first, poll.running {
        True, None -> started(poll, start)
        True, Some(_) | False, _ -> poll
      }
      #(poll, PageJoined(subscriber:))
    }
    subscribers.PageLeft(last:, ended:) -> {
      let running = case last {
        True ->
          option.map(poll.running, fn(running) {
            Running(..running, wanted: False)
          })
        False -> poll.running
      }
      #(Poll(..poll, running:), PageLeft(last:, ended:))
    }
  }
}

/// Starts a read when a page is subscribed and none runs; while one runs, says
/// so.
fn polled(
  poll: Poll(item, answer),
  start: Start(answer),
) -> #(Poll(item, answer), Happened(item, answer)) {
  case subscribers.is_empty(poll.subscribers), poll.running {
    True, _ -> #(poll, Nothing)
    False, None -> #(started(poll, start), Nothing)
    False, Some(_) -> #(poll, ReadBusy)
  }
}

/// Starts a read, with the timer of its deadline.
fn started(
  poll: Poll(item, answer),
  start: Start(answer),
) -> Poll(item, answer) {
  let id = poll.next_read
  let owner = poll.owner
  start(fn(answer) { process.send(owner, ReadEnded(read: id, answer:)) })
  let deadline =
    process.send_after(owner, poll.deadline_ms, ReadDeadline(read: id))
  Poll(
    ..poll,
    running: Some(Running(id:, deadline:, wanted: True)),
    next_read: id + 1,
  )
}

/// The read in flight ended by `how`: when its answer is wanted, `how` is what
/// happened; when it is not, nothing is shown and a page that subscribed
/// meanwhile gets a fresh read.
fn ended(
  poll poll: Poll(item, answer),
  start start: Start(answer),
  how how: Happened(item, answer),
) -> #(Poll(item, answer), Happened(item, answer)) {
  case poll.running {
    None -> #(poll, Nothing)
    Some(Running(deadline:, wanted:, ..)) -> {
      process.cancel_timer(deadline)
      let poll = Poll(..poll, running: None)
      case wanted {
        True -> #(poll, how)
        False -> polled(poll, start)
      }
    }
  }
}

/// A process whose messages are `Message(item, answer)`: `initial` makes its
/// state from its own subject, and `handle` is its message handler, which asks
/// `handle` above what each message did.
pub fn start(
  initial initial: fn(Subject(Message(item, answer))) -> state,
  handle handle: fn(state, Message(item, answer)) ->
    actor.Next(state, Message(item, answer)),
) -> Result(actor.Started(Subject(Message(item, answer))), actor.StartError) {
  actor.start(builder(initial, handle))
}

/// The same as a child of a supervisor, registered under `name` so that a
/// restarted process is reached by the same subject.
pub fn supervised(
  initial initial: fn(Subject(Message(item, answer))) -> state,
  handle handle: fn(state, Message(item, answer)) ->
    actor.Next(state, Message(item, answer)),
  name name: Name(Message(item, answer)),
) -> supervision.ChildSpecification(Subject(Message(item, answer))) {
  supervision.worker(fn() {
    actor.start(actor.named(builder(initial, handle), name))
  })
  |> supervision.timeout(shutdown_ms)
}

fn builder(
  initial: fn(Subject(Message(item, answer))) -> state,
  handle: fn(state, Message(item, answer)) ->
    actor.Next(state, Message(item, answer)),
) -> actor.Builder(state, Message(item, answer), Subject(Message(item, answer))) {
  actor.new_with_initialiser(initialiser_ms, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> subscribers.select_ended(Pages)
    initial(self)
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
}

/// Subscribes a page: it is sent what the process shows, each time that
/// changes.
pub fn subscribe(
  poll poll: Subject(Message(item, answer)),
  subscriber subscriber: Subject(item),
) -> Nil {
  process.send(poll, Pages(subscribers.Join(subscriber:)))
}

/// Takes a page's subscription back.
pub fn unsubscribe(
  poll poll: Subject(Message(item, answer)),
  subscriber subscriber: Subject(item),
) -> Nil {
  process.send(poll, Pages(subscribers.Leave(subscriber:)))
}

/// A tick without the timer: reads now when a page is subscribed and no read
/// runs.
pub fn read_now(poll poll: Subject(Message(item, answer))) -> Nil {
  process.send(poll, ReadNow)
}

/// The deadline of the read in flight, now: the read is ended as if its time had
/// come. Nothing happens when no read runs.
pub fn deadline_now(poll poll: Subject(Message(item, answer))) -> Nil {
  process.send(poll, DeadlineNow)
}

/// How many pages are subscribed, as of the process's handling of everything
/// sent to it before this. Waits as long as the process takes.
pub fn subscriber_count(poll poll: Subject(Message(item, answer))) -> Int {
  process.call_forever(poll, fn(reply) { Pages(subscribers.Count(reply:)) })
}
