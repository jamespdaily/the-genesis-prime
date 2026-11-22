//// When a periodic row's ticks land (`genesis_prime/game/ticking`). The schedule is the
//// server's own guess (`spell.tick_timing`: the client never times a tick), decided on
//// issue 336: tick k lands delay + k * tickTime after the go, for k from 1 to
//// durationTime / tickTime rounded down.

import client_tables
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan
import genesis_prime/game/ticking.{
  type Schedule, NoTick, Schedule, Ticks, UntilRemoved, UntilTheNodeEnds,
}
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import qcheck

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

pub fn ticks_past_the_rows_life_are_cut_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects 82888 (table_rows -- Spell4Effects spellId=38514): delayTime 1000,
  // tickTime 1000, durationTime 4000.
  let assert Ok(atomic_surge) =
    ticking.schedule_of(
      row: LastingRow(delay_ms: 1000, duration_ms: 4000, until_removed: False),
      tick_ms: 1000,
    )
  assert tick_times(
      schedule: ticking.within_life(
        schedule: atomic_surge,
        longer_of_delay_and_duration: False,
      ),
      from_ms: 0,
    )
    == [2000, 3000, 4000, 5000]
    as "a life of delay plus durationTime, 5000 ms, holds every tick"
  assert tick_times(
      schedule: ticking.within_life(
        schedule: atomic_surge,
        longer_of_delay_and_duration: True,
      ),
      from_ms: 0,
    )
    == [2000, 3000, 4000]
    as "a life of the longer of the two, 4000 ms (`0x140568540`), drops the tick due at 5000 ms"
  let assert Ok(late) =
    ticking.schedule_of(
      row: LastingRow(delay_ms: 3000, duration_ms: 2000, until_removed: False),
      tick_ms: 1000,
    )
  assert tick_times(
      schedule: ticking.within_life(
        schedule: late,
        longer_of_delay_and_duration: True,
      ),
      from_ms: 0,
    )
    == []
    as "a delay longer than durationTime is the whole life, 3000 ms, and the first tick lands after it"
}

/// The first ticks of a schedule that has some, at most 20: an open schedule has no last
/// one, so `tick_times` would not end on it.
fn first_tick_times(
  schedule schedule: Schedule,
  from_ms from_ms: Int,
) -> List(Int) {
  int.range(from: 20, to: 0, with: [], run: fn(times, tick) {
    case ticking.next_tick(schedule:, tick: tick - 1) {
      Some(next) if next == tick -> [
        ticking.tick_at_ms(schedule:, from_ms:, tick:),
        ..times
      ]
      Some(_) | None -> times
    }
  })
}

/// An open schedule of this delay and tickTime (a row with flags bit 2 has no durationTime).
fn open(delay_ms delay_ms: Int, tick_ms tick_ms: Int) -> Schedule {
  Schedule(delay_ms:, tick_ms:, duration_ms: 0, count: UntilTheNodeEnds)
}

pub fn an_open_schedule_cut_to_a_nodes_end_keeps_every_tick_up_to_it_and_none_after_test() -> Nil {
  use <- owned_test.run(30_000)
  // The schedule rule is the server's guess (tick k lands delay plus k tick times after the
  // go, `ticking`'s doc); the cast rule fires its due ticks before its ended nodes
  // (`cast.fire`), so a tick due at the end millisecond lands.
  qcheck.given(
    qcheck.tuple4(
      qcheck.bounded_int(from: 0, to: 3000),
      qcheck.bounded_int(from: 1, to: 2000),
      qcheck.bounded_int(from: 0, to: 10_000),
      qcheck.bounded_int(from: -5000, to: 60_000),
    ),
    fn(drawn) {
      let #(delay_ms, tick_ms, go_ms, ends_ms) = drawn
      let cut =
        ticking.ending_with_node(
          schedule: open(delay_ms:, tick_ms:),
          from_ms: go_ms,
          life: lasting.EndsAt(ms: ends_ms),
        )
      let assert Schedule(count: Ticks(kept), ..) = cut
        as "a node with an end gives a schedule with a count"
      let times = tick_times(schedule: cut, from_ms: go_ms)
      assert list.length(times) == kept
        as "the schedule has as many ticks as its count"
      assert list.all(times, fn(at_ms) { at_ms <= ends_ms })
        as "every kept tick lands at or before the node's end"
      assert ticking.tick_at_ms(schedule: cut, from_ms: go_ms, tick: kept + 1)
        > ends_ms
        as "the first tick after the kept ones lands after the node's end"
    },
  )
}

pub fn an_open_schedule_is_cut_by_a_node_that_ends_alone_and_a_finite_one_and_within_life_leave_it_be_test() -> Nil {
  use <- owned_test.run(60_000)
  let tick_times_of_cut = fn(life) {
    first_tick_times(
      schedule: ticking.ending_with_node(
        schedule: open(delay_ms: 1000, tick_ms: 1000),
        from_ms: 1000,
        life:,
      ),
      from_ms: 1000,
    )
  }
  assert tick_times_of_cut(lasting.NoLife) == []
    as "a node with no life ends at the go: no tick"
  assert tick_times_of_cut(lasting.EndsAt(ms: 4500)) == [3000, 4000]
    as "a node ending at 4500, go at 1000, delay 1000, tick 1000: ticks at 3000 and 4000 and none at 5000"
  let held_open =
    ticking.ending_with_node(
      schedule: open(delay_ms: 1000, tick_ms: 1000),
      from_ms: 1000,
      life: lasting.UntilRemoved,
    )
  assert held_open == open(delay_ms: 1000, tick_ms: 1000)
    as "a node that ends only when removed leaves the schedule open"
  assert ticking.next_tick(schedule: held_open, tick: 9999) == Some(10_000)
    as "an open schedule still has a tick at 10,000"
  let assert Ok(finite) =
    ticking.schedule_of(
      row: LastingRow(delay_ms: 0, duration_ms: 3000, until_removed: False),
      tick_ms: 1000,
    )
  assert ticking.ending_with_node(
      schedule: finite,
      from_ms: 0,
      life: lasting.EndsAt(ms: 1500),
    )
    == finite
    as "a schedule with a count is not cut by a node"
  list.each([False, True], fn(longer) {
    assert ticking.within_life(
        schedule: open(delay_ms: 1000, tick_ms: 1000),
        longer_of_delay_and_duration: longer,
      )
      == open(delay_ms: 1000, tick_ms: 1000)
      as "a life no row bounds: within_life leaves an open schedule as it is (delay 1000, tick 1000, duration 0 gave 0 ticks before)"
  })
  case client_tables.present() {
    True -> rows_that_last_until_removed_read_as_open_schedules()
    False -> Nil
  }
}

/// Spell4Effects 210304 (delay 1000, tickTime 1000), 217944 (0, 500) and 210337 (0, 250):
/// each has flags bit 2 and no durationTime (`table_rows -- Spell4Effects 210304 217944
/// 210337`), read from the client's tables, which the committed fixture does not hold.
fn rows_that_last_until_removed_read_as_open_schedules() -> Nil {
  let tables = client_tables.shared()
  list.each(
    [#(210_304, 1000, 1000), #(217_944, 0, 500), #(210_337, 0, 250)],
    fn(expected) {
      let #(row_id, delay_ms, tick_ms) = expected
      let assert Ok(row) =
        spell4_effects.get(tables:, id: Spell4EffectsId(row_id))
        as "the client's table holds the row"
      assert row.tick_time == tick_ms
        && row.delay_time == delay_ms
        && row.duration_time == 0
        as "the row's own delay, tickTime and no durationTime"
      let lasting_row = spell_plan.lasting_row_of(effect: row)
      assert ticking.open_schedule_of(row: lasting_row, tick_ms:)
        == open(delay_ms:, tick_ms:)
        as "the open reader keeps the row's delay, tickTime and durationTime 0"
      assert ticking.schedule_of(row: lasting_row, tick_ms:)
        == Error(UntilRemoved)
        as "the damage and heal reading still refuses a row that lasts until removed"
    },
  )
}
