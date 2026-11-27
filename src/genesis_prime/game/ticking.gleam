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
//// - **A row with flags bit 2 lasts until removed** (`Spell4Effects.effectType.8.periodic`);
////   every periodic row with a durationTime of 0 has the bit. A damage or heal row
////   that lasts until removed has no schedule (`schedule_of`).
//// - **A periodic Proxy with flags bit 2 ticks every tickTime until its holder spell is
////   removed** (`Spell4Effects.effectType.26.periodic`): its open schedule
////   (`open_schedule_of`) has no count, and `ending_with_node` cuts it at the go to the end
////   of the node when the node has one, an aura's (`life_under_aura`, `0x1407180c0`).

import genesis_prime/game/lasting
import genesis_prime/game/lasts
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
  /// No count: a periodic Proxy row with flags bit 2 ticks every tickTime until its holder
  /// spell is removed (`Spell4Effects.effectType.26.periodic`) or its node ends.
  UntilTheNodeEnds
}

/// Why a periodic row has no schedule.
pub type ScheduleError {
  /// Flags bit 2: the row lasts until removed.
  UntilRemoved
  /// A life shorter than one tick, or a tickTime of 0 on an open row; no row has the
  /// first, so the load fails.
  NoTick(tick_ms: Int, duration_ms: Int)
}

/// The schedule of a row whose tickTime is `tick_ms`, from its delay and durationTime.
/// A row that lasts until removed has none (`open_schedule_of` reads a Proxy's).
pub fn schedule_of(
  row row: lasting.LastingRow,
  tick_ms tick_ms: Int,
) -> Result(Schedule, ScheduleError) {
  case row.lasts {
    lasts.UntilRemoved -> Error(UntilRemoved)
    lasts.For(duration_ms:) -> {
      let count = case tick_ms > 0 {
        True -> duration_ms / tick_ms
        False -> 0
      }
      use <- bool.guard(
        when: count < 1,
        return: Error(NoTick(tick_ms:, duration_ms:)),
      )
      Ok(Schedule(
        delay_ms: row.delay_ms,
        tick_ms:,
        duration_ms:,
        count: Ticks(count),
      ))
    }
  }
}

/// The open schedule of a periodic Proxy row with flags bit 2 and a tickTime of `tick_ms`:
/// its delay and tickTime, with no durationTime and no count, since the row ticks until its holder
/// spell is removed (`Spell4Effects.effectType.26.periodic`). A tickTime of 0 has none, as in
/// `schedule_of`: a tick due at every moment would never end. The caller decides which rows
/// are read as open; a damage or heal row that lasts until removed still has none
/// (`schedule_of`).
pub fn open_schedule_of(
  row row: lasting.LastingRow,
  tick_ms tick_ms: Int,
) -> Result(Schedule, ScheduleError) {
  use <- bool.guard(
    when: tick_ms < 1,
    return: Error(NoTick(tick_ms:, duration_ms: 0)),
  )
  Ok(Schedule(
    delay_ms: row.delay_ms,
    tick_ms:,
    duration_ms: 0,
    count: UntilTheNodeEnds,
  ))
}

/// Whether the schedule has no count, so its row's node lasts until removed
/// (`lasts.UntilRemoved` in `lasting.LastingRow.lasts`) and no durationTime bounds it.
pub fn lasts_until_removed(schedule schedule: Schedule) -> Bool {
  case schedule.count {
    UntilTheNodeEnds -> True
    Ticks(_) -> False
  }
}

/// The schedule cut to the ticks that land within the row's own life from the go, the
/// life its node on the unit takes from it (`lasting.lifetime_of`). For a spell whose
/// life is the longer of delay and durationTime (`0x140568540`) that drops the ticks past
/// it, so no tick is due after its node's life however late it is looked at; whether the
/// client would show a 0x7f8 after its node ends is not read. An open schedule has no
/// life a row bounds and is left as it is (`ending_with_node`).
pub fn within_life(
  schedule schedule: Schedule,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> Schedule {
  let assert Some(life_ms) =
    lasting.lifetime_of(
      row: lasting.LastingRow(
        delay_ms: schedule.delay_ms,
        lasts: lasts.For(duration_ms: schedule.duration_ms),
      ),
      longer_of_delay_and_duration:,
    )
    as "a row that times out has a lifetime"
  let within = case schedule.tick_ms > 0 {
    True -> { life_ms - schedule.delay_ms } / schedule.tick_ms
    False -> 0
  }
  case schedule.count {
    Ticks(count) ->
      Schedule(..schedule, count: Ticks(int.clamp(within, min: 0, max: count)))
    UntilTheNodeEnds -> schedule
  }
}

/// An open schedule cut to the life of the node it ticks on, for a go at `from_ms`: with
/// `EndsAt` every tick at or before the end stays and none after (a tick due at the end
/// millisecond lands before the node ends, since the cast rule fires its due ticks before
/// its ended nodes), with `NoLife` none stays, and with `UntilRemoved` it stays open. A
/// schedule with a count is left as it is.
pub fn ending_with_node(
  schedule schedule: Schedule,
  from_ms from_ms: Int,
  life life: lasting.Life,
) -> Schedule {
  case schedule.count, life {
    Ticks(_), _ | UntilTheNodeEnds, lasting.UntilRemoved -> schedule
    UntilTheNodeEnds, lasting.NoLife -> Schedule(..schedule, count: Ticks(0))
    UntilTheNodeEnds, lasting.EndsAt(ms:) -> {
      let ticks = case schedule.tick_ms > 0 {
        True -> { ms - from_ms - schedule.delay_ms } / schedule.tick_ms
        False -> 0
      }
      Schedule(..schedule, count: Ticks(int.max(0, ticks)))
    }
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

/// The tick after `tick` (0 before the first), or `None` after the last; an open schedule
/// has no last.
pub fn next_tick(schedule schedule: Schedule, tick tick: Int) -> Option(Int) {
  case schedule.count {
    Ticks(count) if tick < count -> Some(tick + 1)
    Ticks(_) -> None
    UntilTheNodeEnds -> Some(tick + 1)
  }
}

/// The periodic rows' timing the client's code does not show: the client has no tick timer,
/// so the schedule of a damage or heal tick is the server's guess, and the client's
/// behaviour for a tick past its node's life is not known. A periodic Proxy that lasts
/// until removed ticks until its node ends, an aura's at the aura's end; the end of a damage
/// or heal over time that lasts until removed stays left out.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Periodic effects",
      missing: "the time of each tick of a damage or heal over time and of each cast of a periodic Proxy, which the client does not time and the server schedules by a guess, dropping a tick that would land after its node ends without knowing whether the client shows one; a periodic Proxy that lasts until removed ticks every tickTime until its node ends, and the end of a heal or damage over time that lasts until removed is left out",
    ),
  ]
}
