//// When a periodic row's ticks land (`genesis_prime/game/ticking`). The schedule is the
//// server's own guess (`spell.tick_timing`: the client never times a tick), decided on
//// issue 336: tick k lands delay + k * tickTime after the go, for k from 1 to
//// durationTime / tickTime rounded down.

import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/ticking.{type Schedule, NoTick, UntilRemoved}
import gleam/list
import gleam/option.{None, Some}
import owned_test

/// Every tick of a schedule, from the go at `from_ms`.
fn tick_times(schedule schedule: Schedule, from_ms from_ms: Int) -> List(Int) {
  tick_times_after(schedule:, from_ms:, tick: 0, times: [])
}

fn tick_times_after(
  schedule schedule: Schedule,
  from_ms from_ms: Int,
  tick tick: Int,
  times times: List(Int),
) -> List(Int) {
  case ticking.next_tick(schedule:, tick:) {
    None -> list.reverse(times)
    Some(next) ->
      tick_times_after(schedule:, from_ms:, tick: next, times: [
        ticking.tick_at_ms(schedule:, from_ms:, tick: next),
        ..times
      ])
  }
}

pub fn ticks_land_at_delay_plus_each_whole_tick_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(no_delay) =
    ticking.schedule_of(
      row: LastingRow(delay_ms: 0, duration_ms: 6000, until_removed: False),
      tick_ms: 2000,
    )
  assert tick_times(schedule: no_delay, from_ms: 10_000)
    == [12_000, 14_000, 16_000]
    as "delay 0, tickTime 2000, durationTime 6000: a tick each 2000 ms after the go, the last at the life's end"
  let assert Ok(delayed) =
    ticking.schedule_of(
      row: LastingRow(delay_ms: 1500, duration_ms: 6000, until_removed: False),
      tick_ms: 1500,
    )
  assert tick_times(schedule: delayed, from_ms: 0) == [3000, 4500, 6000, 7500]
    as "delay 1500, tickTime 1500, durationTime 6000: four ticks, the first a tick after the delay"
  let assert Ok(part) =
    ticking.schedule_of(
      row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
      tick_ms: 2000,
    )
  assert tick_times(schedule: part, from_ms: 0) == [2000, 4000]
    as "durationTime 5000, tickTime 2000: two whole ticks; the half tick left over lands none"
  assert ticking.schedule_of(
      row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
      tick_ms: 1000,
    )
    == Error(UntilRemoved)
    as "flags bit 2: the row lasts until removed, which no schedule ends (issue 803)"
  assert ticking.schedule_of(
      row: LastingRow(delay_ms: 0, duration_ms: 500, until_removed: False),
      tick_ms: 1000,
    )
    == Error(NoTick(tick_ms: 1000, duration_ms: 500))
    as "a life shorter than one tick has no tick, which fails the load"
}
