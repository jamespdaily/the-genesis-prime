//// What a connection's timer for the earliest of several deadlines is told when that
//// earliest deadline moves: the quest log's (genesis_prime/game/quest_log
//// `next_deadline`) and the held items' (genesis_prime/game/item_expiry `next_deadline`)
//// each keep one timer, started for the earliest deadline and moved when it changes.

import gleam/int
import gleam/option.{type Option, None, Some}

/// What the timer is told when the earliest deadline moves.
pub type DeadlineTimer {
  /// Start the timer, which is not running, to fire in this many milliseconds.
  StartDeadlineTimer(after_ms: Int)
  /// Cancel the running timer.
  CancelDeadlineTimer
}

/// What the timer needs when the earliest deadline (on any one clock, the one `now_ms` is
/// read on) goes from `before`, the deadline the running timer is set for, or none when no
/// timer runs, to `after`: nothing when it did not move, the timer started when none ran, the
/// running one cancelled and then started for the new deadline, or only cancelled when none is
/// left. A timer that has just fired or been cancelled is not running.
pub fn moved(
  before before: Option(Int),
  after after: Option(Int),
  now_ms now_ms: Int,
) -> List(DeadlineTimer) {
  case before, after {
    None, None -> []
    None, Some(deadline_ms) -> [
      StartDeadlineTimer(after_ms: int.max(0, deadline_ms - now_ms)),
    ]
    Some(_), None -> [CancelDeadlineTimer]
    Some(was), Some(deadline_ms) if was == deadline_ms -> []
    Some(_), Some(deadline_ms) -> [
      CancelDeadlineTimer,
      StartDeadlineTimer(after_ms: int.max(0, deadline_ms - now_ms)),
    ]
  }
}
