//// The pages a dashboard process serves with what it reads, and the one timer
//// chain that reads while any page is subscribed. The Overview's poller
//// (`host`) and each log follower (`follow`) keep their pages here.
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

/// What a page's join did: it was the first (the timer chain started), a later
/// one, or already subscribed (nothing changed).
pub type Joined(item, message) {
  FirstJoined(Subscribers(item, message))
  LaterJoined(Subscribers(item, message))
  AlreadyJoined
}

/// What a leave did: the last page left (the timer chain ended), or pages
/// remain or none left.
pub type Left(item, message) {
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
pub fn count(subscribers: Subscribers(item, message)) -> Int {
  list.length(subscribers.entries)
}

/// Whether no page is subscribed.
pub fn is_empty(subscribers: Subscribers(item, message)) -> Bool {
  subscribers.entries == []
}

/// Subscribes a page and monitors it; the first page starts the timer chain.
pub fn join(
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

/// Takes a page's subscription back; the last page to leave ends the timer
/// chain.
pub fn leave(
  subscribers subscribers: Subscribers(item, message),
  subscriber subscriber: Subject(item),
) -> Left(item, message) {
  leaving(subscribers, fn(entry) { entry.subject == subscriber })
}

/// Drops the page whose monitor reported it ended; the last page to leave ends
/// the timer chain.
pub fn leave_ended(
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
