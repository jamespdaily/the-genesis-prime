//// When a periodic row's ticks land, worked out once from its row when the tables
//// load (genesis_prime/game/spell_area for damage, genesis_prime/game/spell_plan for
//// heals). The cast rule (genesis_prime/game/cast) arms one tick at a time from it.
////
//// - **The client has no tick timer** (`spell.tick_timing`): it reads tickTime only
////   for the tooltip and the periodic flag of a result, so the schedule is the
////   server's own. A guess, until a retail recording of one damage-over-time spell
////   gives the go and each 0x7f8 with its time (issue 336): tick k of `count` lands
////   `delay_ms + k * tick_ms` after the go, for k from 1 to durationTime / tickTime
////   rounded down.
//// - **A row with flags bit 2 lasts until removed** (`Spell4Effects.effectType.8.periodic`),
////   which no schedule ends (issue 803); every periodic row with a durationTime of 0
////   has the bit.

import genesis_prime/game/lasting
import gleam/option.{type Option}

/// When a periodic row's ticks land: tick k of `count` lands `delay_ms + k * tick_ms`
/// after the go.
pub type Schedule {
  Schedule(delay_ms: Int, tick_ms: Int, count: Int)
}

/// Why a periodic row has no schedule.
pub type ScheduleError {
  /// Flags bit 2: the row lasts until removed (issue 803).
  UntilRemoved
  /// A life shorter than one tick; no row has one, so the load fails.
  NoTick(tick_ms: Int, duration_ms: Int)
}

/// The schedule of a row whose tickTime is `tick_ms`, from its delay and durationTime.
pub fn schedule_of(
  row row: lasting.LastingRow,
  tick_ms tick_ms: Int,
) -> Result(Schedule, ScheduleError) {
  todo as "#785: the schedule of a periodic row"
}

/// The monotonic time tick `tick` lands at, for a go at `from_ms`.
pub fn tick_at_ms(
  schedule schedule: Schedule,
  from_ms from_ms: Int,
  tick tick: Int,
) -> Int {
  todo as "#785: the time of a tick"
}

/// The tick after `tick` (0 before the first), or `None` after the last.
pub fn next_tick(schedule schedule: Schedule, tick tick: Int) -> Option(Int) {
  todo as "#785: the tick after a tick"
}
