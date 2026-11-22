//// When a periodic row's ticks land, worked out once from its row when the tables
//// load (genesis_prime/game/spell_area for damage, genesis_prime/game/spell_plan for
//// heals). The cast rule (genesis_prime/game/cast) arms one tick at a time from it.
////
//// - **The client has no tick timer** (`spell.tick_timing`): it reads tickTime only
////   for the tooltip and the periodic flag of a result, so the schedule is the
////   server's own. A guess: no retail recording of one damage-over-time spell
////   gives the go and each 0x7f8 with its time: tick k of `count` lands
////   `delay_ms + k * tick_ms` after the go, for k from 1 to durationTime / tickTime
////   rounded down, and only within the row's life (`within_life`).
//// - **A row with flags bit 2 lasts until removed** (`Spell4Effects.effectType.8.periodic`),
////   which no schedule ends; every periodic row with a durationTime of 0
////   has the bit.

import genesis_prime/game/lasting
import genesis_prime/gap
import gleam/bool
import gleam/int
import gleam/option.{type Option, None, Some}

/// When a periodic row's ticks land: tick k of `count` lands `delay_ms + k * tick_ms`
/// after the go. `duration_ms` is the row's durationTime, which with its delay gives the
/// life of the row's node on the unit, as the client's own end timer for the effect counts
/// it (`opcode.0x7f4.effect_time`).
pub type Schedule {
  Schedule(delay_ms: Int, tick_ms: Int, duration_ms: Int, count: Count)
}

/// How many ticks a schedule has.
pub type Count {
  /// This many ticks, the last landing within the row's durationTime.
  Ticks(Int)
  /// No count: the row has flags bit 2 and ticks until its node ends.
  UntilTheNodeEnds
}

/// Why a periodic row has no schedule.
pub type ScheduleError {
  /// Flags bit 2: the row lasts until removed.
  UntilRemoved
  /// A life shorter than one tick; no row has one, so the load fails.
  NoTick(tick_ms: Int, duration_ms: Int)
}

/// The schedule of a row whose tickTime is `tick_ms`, from its delay and durationTime.
pub fn schedule_of(
  row row: lasting.LastingRow,
  tick_ms tick_ms: Int,
) -> Result(Schedule, ScheduleError) {
  use <- bool.guard(when: row.until_removed, return: Error(UntilRemoved))
  let count = case tick_ms > 0 {
    True -> row.duration_ms / tick_ms
    False -> 0
  }
  use <- bool.guard(
    when: count < 1,
    return: Error(NoTick(tick_ms:, duration_ms: row.duration_ms)),
  )
  Ok(Schedule(
    delay_ms: row.delay_ms,
    tick_ms:,
    duration_ms: row.duration_ms,
    count: Ticks(count),
  ))
}

/// The schedule cut to the ticks that land within the row's own life from the go, the
/// life its node on the unit takes from it (`lasting.lifetime_of`). For a spell whose
/// life is the longer of delay and durationTime (`0x140568540`) that drops the ticks past
/// it, so no tick is due after its node's life however late it is looked at; whether the
/// client would show a 0x7f8 after its node ends is not read.
pub fn within_life(
  schedule schedule: Schedule,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> Schedule {
  let life_ms =
    lasting.lifetime_of(
      row: lasting.LastingRow(
        delay_ms: schedule.delay_ms,
        duration_ms: schedule.duration_ms,
        until_removed: False,
      ),
      longer_of_delay_and_duration:,
    )
  let within = case schedule.tick_ms > 0 {
    True -> { life_ms - schedule.delay_ms } / schedule.tick_ms
    False -> 0
  }
  case schedule.count {
    Ticks(count) ->
      Schedule(..schedule, count: Ticks(int.clamp(within, min: 0, max: count)))
    UntilTheNodeEnds -> Schedule(..schedule, count: Ticks(0))
  }
}

/// The monotonic time tick `tick` lands at, for a go at `from_ms`.
pub fn tick_at_ms(
  schedule schedule: Schedule,
  from_ms from_ms: Int,
  tick tick: Int,
) -> Int {
  from_ms + schedule.delay_ms + tick * schedule.tick_ms
}

/// The tick after `tick` (0 before the first), or `None` after the last.
pub fn next_tick(schedule schedule: Schedule, tick tick: Int) -> Option(Int) {
  case schedule.count {
    Ticks(count) if tick < count -> Some(tick + 1)
    Ticks(_) | UntilTheNodeEnds -> None
  }
}

/// The periodic rows' timing the client's code does not show: the client has no tick timer,
/// so the schedule of a damage or heal tick is the server's guess, and the client's
/// behaviour for a tick past its node's life is not known.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Periodic effects",
      missing: "the time of each tick of a damage or heal over time and of each cast of a periodic Proxy, which the client does not time and the server schedules by a guess, dropping a tick that would land after its node ends without knowing whether the client shows one",
    ),
  ]
}
