//// A timer the test drives: the arm a dashboard process is given in place of
//// `subscribers.send_after`. Each timer armed or cancelled is a message to the
//// test, and a timer never fires by itself: the test fires it by sending the
//// process its tick, so no test waits on a clock.
////
//// The process has handled every message sent to it before a call to it
//// returns, and its sends to the test are ordered with its reply, so after such
//// a call the timers it armed or cancelled are already in the test's mailbox.

import genesis_prime/dashboard/subscribers
import gleam/erlang/process.{type Subject}

/// What the process did to its timers.
pub type Event {
  /// A timer was armed: `fire` sends the process the tick the timer would, and
  /// `timer` names the timer in `Cancelled`.
  Armed(timer: Subject(Nil), after_ms: Int, fire: fn() -> Nil)
  /// The timer was cancelled.
  Cancelled(timer: Subject(Nil))
}

/// An arm that tells `events` of each timer armed and cancelled.
pub fn arm(events events: Subject(Event)) -> subscribers.Arm(message) {
  fn(to, after_ms, message) {
    let timer = process.new_subject()
    process.send(
      events,
      Armed(timer:, after_ms:, fire: fn() { process.send(to, message) }),
    )
    fn() {
      process.send(events, Cancelled(timer:))
      Nil
    }
  }
}

/// The next event, or an error when none has been sent. Call it after a call to
/// the process has returned.
pub fn next(events events: Subject(Event)) -> Result(Event, Nil) {
  process.receive(events, 0)
}

/// The timer armed next; fails when the process armed none.
pub fn next_armed(events events: Subject(Event)) -> Event {
  let assert Ok(Armed(..) as armed) = next(events:)
    as "the process armed no timer"
  armed
}

/// Fires an armed timer.
pub fn fire(armed armed: Event) -> Nil {
  let assert Armed(fire:, ..) = armed as "only an armed timer fires"
  fire()
}
