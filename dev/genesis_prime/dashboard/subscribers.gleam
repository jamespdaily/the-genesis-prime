//// The pages a dashboard process serves with what it reads, and the one timer
//// chain that reads while any page is subscribed. The Overview's poller and
//// each log follower (`read_poll`, `follow`) keep their pages here, and take
//// their pages' requests through `handle`.
////
//// ```text
//// page runtime ──join──► Subscribers ──arm──► timer ──Tick(chain)──► the process
////                           ▲                                           │
////                           └──────────── next_tick(chain) ◄────────────┘
//// ```
////
//// - A page is monitored when it joins; a page that joins twice is one page.
//// - The first page to join starts a timer chain, and the last to leave ends
////   it. Each tick arms the next, so exactly one timer is pending while a page
////   is subscribed.
//// - A tick carries the number of the chain that armed it, and a tick of an
////   earlier chain (one already in the mailbox when its timer was cancelled)
////   is refused, so it never starts a second chain.
//// - A page asks to join or leave, a page's end is reported by its monitor, and
////   the process is asked for the count, all as one `Request` that the process
////   wraps in a variant of its own messages; `handle` says what each did.
//// - The timers are armed through `Arm`, which a test replaces to hold and send
////   the ticks itself.

import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Arms one timer: after the given milliseconds the message is sent to the
/// subject, once. The result cancels the timer.
pub type Arm(message) =
  fn(Subject(message), Int, message) -> fn() -> Nil

/// The arm that is a real timer.
pub fn send_after(
  to subject: Subject(message),
  after_ms after_ms: Int,
  message message: message,
) -> fn() -> Nil {
  let timer = process.send_after(subject, after_ms, message)
  fn() {
    process.cancel_timer(timer)
    Nil
  }
}

type Entry(item) {
  Entry(subject: Subject(item), monitor: process.Monitor)
}

/// The subscribed pages of one process, each reached by a `Subject(item)`, and
/// that process's timer chain; `message` is the process's own message type.
pub opaque type Subscribers(item, message) {
  Subscribers(
    owner: Subject(message),
    interval_ms: Int,
    arm: Arm(message),
    tick: fn(Int) -> message,
    entries: List(Entry(item)),
    chain: Int,
    cancel: Option(fn() -> Nil),
  )
}

/// What a page, the runtime or a test asks of a process's subscribers.
pub type Request(item) {
  Join(subscriber: Subject(item))
  Ended(down: process.Down)
  Count(reply: Subject(Int))
}

/// What a request did, for the process to act on: a page joined (the first one
/// started the timer chain), a page ended (the last one ended the chain), or
/// nothing changed (a page that joined twice, or a count, which is
/// answered).
pub type Handled(item) {
  PageJoined(subscriber: Subject(item), first: Bool)
  PageLeft(last: Bool)
  Unchanged
}

/// What a page's join did: it was the first (the timer chain started), a later
/// one, or already subscribed (nothing changed).
type Joined(item, message) {
  FirstJoined(Subscribers(item, message))
  LaterJoined(Subscribers(item, message))
  AlreadyJoined
}

/// What a page's end did: the last page left (the timer chain ended), or pages
/// remain or none left.
type Left(item, message) {
  LastLeft(Subscribers(item, message))
  StillSubscribed(Subscribers(item, message))
}

/// No page subscribed and no timer. `tick` makes the process's own message from
/// the number of a chain; the process sends itself that message through `arm`.
pub fn new(
  owner owner: Subject(message),
  interval_ms interval_ms: Int,
  arm arm: Arm(message),
  tick tick: fn(Int) -> message,
) -> Subscribers(item, message) {
  Subscribers(
    owner:,
    interval_ms:,
    arm:,
    tick:,
    entries: [],
    chain: 0,
    cancel: None,
  )
}

/// The pages' subjects, the newest page first.
pub fn subjects(
  subscribers: Subscribers(item, message),
) -> List(Subject(item)) {
  list.map(subscribers.entries, fn(entry) { entry.subject })
}

/// How many pages are subscribed.
fn count(subscribers: Subscribers(item, message)) -> Int {
  list.length(subscribers.entries)
}

/// Whether no page is subscribed.
pub fn is_empty(subscribers: Subscribers(item, message)) -> Bool {
  subscribers.entries == []
}

/// Does what a request asks, and says what it did.
pub fn handle(
  subscribers subscribers: Subscribers(item, message),
  request request: Request(item),
) -> #(Subscribers(item, message), Handled(item)) {
  case request {
    Join(subscriber:) ->
      case join(subscribers:, subscriber:) {
        AlreadyJoined -> #(subscribers, Unchanged)
        FirstJoined(joined) -> #(joined, PageJoined(subscriber:, first: True))
        LaterJoined(joined) -> #(joined, PageJoined(subscriber:, first: False))
      }
    Ended(down:) -> left(leave_ended(subscribers:, monitor: down.monitor))
    Count(reply:) -> {
      process.send(reply, count(subscribers))
      #(subscribers, Unchanged)
    }
  }
}

fn left(
  left: Left(item, message),
) -> #(Subscribers(item, message), Handled(item)) {
  case left {
    LastLeft(remaining) -> #(remaining, PageLeft(last: True))
    StillSubscribed(remaining) -> #(remaining, PageLeft(last: False))
  }
}

/// Adds to a selector the reports that a subscribed page ended, each wrapped
/// in the process's own message.
pub fn select_ended(
  selector selector: process.Selector(message),
  wrap wrap: fn(Request(item)) -> message,
) -> process.Selector(message) {
  process.select_monitors(selector, fn(down) { wrap(Ended(down)) })
}

/// Subscribes a page and monitors it; the first page starts the timer chain.
fn join(
  subscribers subscribers: Subscribers(item, message),
  subscriber subscriber: Subject(item),
) -> Joined(item, message) {
  let already =
    list.any(subscribers.entries, fn(entry) { entry.subject == subscriber })
  case already {
    True -> AlreadyJoined
    False -> {
      let assert Ok(pid) = process.subject_owner(subscriber)
        as "a page's subject has an owner"
      let entry = Entry(subject: subscriber, monitor: process.monitor(pid))
      let first = subscribers.entries == []
      let subscribers =
        Subscribers(..subscribers, entries: [entry, ..subscribers.entries])
      case first {
        True -> FirstJoined(start_chain(subscribers))
        False -> LaterJoined(subscribers)
      }
    }
  }
}

/// Drops the page whose monitor reported it ended; the last page to leave ends
/// the timer chain.
fn leave_ended(
  subscribers subscribers: Subscribers(item, message),
  monitor monitor: process.Monitor,
) -> Left(item, message) {
  leaving(subscribers, fn(entry) { entry.monitor == monitor })
}

fn leaving(
  subscribers: Subscribers(item, message),
  leaves: fn(Entry(item)) -> Bool,
) -> Left(item, message) {
  let #(gone, staying) = list.partition(subscribers.entries, leaves)
  list.each(gone, fn(entry) { process.demonitor_process(entry.monitor) })
  let subscribers = Subscribers(..subscribers, entries: staying)
  case gone, staying {
    [], _ | _, [_, ..] -> StillSubscribed(subscribers)
    [_, ..], [] -> LastLeft(end_chain(subscribers))
  }
}

/// A tick arrived: when it is of the current chain, the next tick is armed and
/// the result is the subscribers to read for; a tick of an earlier chain, or of
/// a chain that ended, is an error and changes nothing. Every end or start of a
/// chain gives the next one a new number.
pub fn next_tick(
  subscribers subscribers: Subscribers(item, message),
  chain chain: Int,
) -> Result(Subscribers(item, message), Nil) {
  use <- bool.guard(when: chain != subscribers.chain, return: Error(Nil))
  Ok(arm_next(subscribers))
}

fn start_chain(
  subscribers: Subscribers(item, message),
) -> Subscribers(item, message) {
  arm_next(end_chain(subscribers))
}

fn end_chain(
  subscribers: Subscribers(item, message),
) -> Subscribers(item, message) {
  option.map(subscribers.cancel, fn(cancel) { cancel() })
  Subscribers(..subscribers, chain: subscribers.chain + 1, cancel: None)
}

fn arm_next(
  subscribers: Subscribers(item, message),
) -> Subscribers(item, message) {
  let cancel =
    subscribers.arm(
      subscribers.owner,
      subscribers.interval_ms,
      subscribers.tick(subscribers.chain),
    )
  Subscribers(..subscribers, cancel: Some(cancel))
}
