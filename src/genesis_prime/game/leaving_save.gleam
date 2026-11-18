//// How long a connection that is ending keeps trying to save its player's
//// place when the store gives no answer: the ladder of waits between tries,
//// the deadline as a time, and the decision after each failure. Pure: times
//// are the monotonic milliseconds an input carries, and the rule starts the
//// timer.
////
//// ```
//// an end               ─▶ logout_deadline(now)                 ─▶ ForLogout(now + within_ms)
//// the shell's Stopping ─▶ stopped(deadline, stop_ms)           ─▶ ForStop(stop_ms)
//// a failed ask         ─▶ after_failure(failed, deadline, now) ─▶ RetryAfter(wait_ms) or GiveUp
//// the first stop       ─▶ reconciled(retry_at, now, deadline)  ─▶ Expired, RetryNow or Keep
//// an ask to make       ─▶ ask_within_ms(deadline, now, ask)    ─▶ the time it may take; <= 0 is none
//// ```
////
//// - A retry is made only when its wait ends before the deadline; the deadline
////   decides, and `failed` only indexes the ladder, since each try may take an
////   ask's whole deadline.
//// - A stop's deadline replaces a logout's, whichever is earlier: the stop's is
////   the listener's shutdown bound, which the connection must end inside.
//// - The ladder and the time a logout may try are the server's choice
////   (genesis_prime's settings); the client has no such wait.

/// The ladder of waits between a leaving player's tries, and how long a logout
/// may try. `waits_ms` holds the waits after the first, second and later
/// failures; `then_ms` is every wait past the list.
pub type Retries {
  Retries(within_ms: Int, waits_ms: List(Int), then_ms: Int)
}

/// When a leaving save stops being tried, as a monotonic time. A logout's is
/// `within_ms` after the end began; a stop's is the shell's deadline.
pub type Deadline {
  ForLogout(at_ms: Int)
  ForStop(at_ms: Int)
}

/// What a failed try leads to.
pub type Next {
  RetryAfter(wait_ms: Int)
  GiveUp
}

/// What the first stop does to the retry timer that runs when it arrives.
pub type Reconciled {
  /// The stop's deadline is at or before now: the connection ends.
  Expired
  /// The timer would fire at or after the deadline: it is cancelled and the
  /// ask is made now, within what the deadline leaves.
  RetryNow
  /// The timer fires before the deadline: it goes on.
  Keep
}

/// A logout's deadline: `retries.within_ms` after `now_ms`.
pub fn logout_deadline(_retries: Retries, now_ms _now_ms: Int) -> Deadline {
  panic as "shape only: built with its tests"
}

/// The deadline once a stop's `stop_ms` is known: the first stop's replaces a
/// logout's, also when it is earlier, and a stop's stays.
pub fn stopped(_deadline: Deadline, stop_ms _stop_ms: Int) -> Deadline {
  panic as "shape only: built with its tests"
}

/// What the first stop does to a retry timer that fires at `retry_at_ms`, under
/// the deadline the stop has set.
pub fn reconciled(
  retry_at_ms _retry_at_ms: Int,
  now_ms _now_ms: Int,
  deadline _deadline: Deadline,
) -> Reconciled {
  panic as "shape only: built with its tests"
}

/// The deadline's time.
pub fn at_ms(_deadline: Deadline) -> Int {
  panic as "shape only: built with its tests"
}

/// How long an ask made at `now_ms` may take: the ask deadline, or what the
/// deadline leaves when that is shorter. Zero or less means no time is left
/// and no ask is made.
pub fn ask_within_ms(
  _deadline: Deadline,
  now_ms _now_ms: Int,
  ask_deadline_ms _ask_deadline_ms: Int,
) -> Int {
  panic as "shape only: built with its tests"
}

/// The wait after `failed` earlier failures: the ladder's entry, then
/// `then_ms` past its end.
pub fn wait_ms(_retries: Retries, failed _failed: Int) -> Int {
  panic as "shape only: built with its tests"
}

/// What a failed try leads to: a retry after `wait_ms(failed)` when that wait
/// ends before the deadline, otherwise giving up. `failed` counts the failures
/// before this one.
pub fn after_failure(
  _retries: Retries,
  failed _failed: Int,
  deadline _deadline: Deadline,
  now_ms _now_ms: Int,
) -> Next {
  panic as "shape only: built with its tests"
}
