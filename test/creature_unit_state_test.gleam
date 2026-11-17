//// A creature's held unit states (`genesis_prime/world_map/creature_unit_state`), run as the
//// pure feature it is: rows in, the holds and what the creature's rule must do out.
//// Expected values come from these places.
//// - Spell4Effects type 15 rows (`table_rows -- Spell4Effects effectType=15`): row 64365
////   (Spell4 32683 "Stun/Immune - 8 seconds": state 6, duration 8500, delay 0), row 204411
////   (Spell4 48565: state 6, delay 500, duration 2000) and the rows of Spell4 4178, which holds
////   states 6 and 13 to 18 at once.
//// - The Design of the step: a hold starts at the go and ends at the go's time plus the row's
////   delay and duration; one timer serves the earliest end; the creature's number for a hold
////   is its own for its life.
//// - What state 6 means (it blocks hostile effects) is the reading table in
////   `genesis_prime/game/unit_state`, a guess from spell names.

import genesis_prime/client_connection.{UnitStateEnded, UnitStateHeld}
import genesis_prime/game/unit_state.{Row}
import genesis_prime/world_map/creature_unit_state.{
  CancelTimer, StartTimer, ToViewers,
}
import owned_test

/// The go of every test, on the map's monotonic clock.
const go_ms = 6000

pub fn a_row_is_held_until_the_go_plus_delay_plus_duration_and_told_to_each_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 64365: state 6 for 8500 ms from the go at 6000, told at 6100: it ends at 14 500.
  let #(state, effects) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  assert effects
    == [
      ToViewers(news: UnitStateHeld(state: 6, number: 1)),
      StartTimer(after_ms: 8400),
    ]
    as "the viewers are told the state, and one timer is set for its end, 8400 ms on"
  assert creature_unit_state.blocks_hostile(state:, now_ms: 14_499)
    as "held until the end"
  assert !creature_unit_state.blocks_hostile(state:, now_ms: 14_500)
    as "not held at the end"
  // Row 204411: a delay of 500 and 2000 ms of duration end at the go plus 2500.
  let #(_, delayed) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 500, duration_ms: 2000)],
      went_at_ms: go_ms,
      now_ms: go_ms,
    )
  assert delayed
    == [
      ToViewers(news: UnitStateHeld(state: 6, number: 1)),
      StartTimer(after_ms: 2500),
    ]
    as "the delay counts from the go and is part of the hold"
}

pub fn a_row_already_past_its_end_is_not_held_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 14_500,
    )
  assert effects == []
    as "an end at the tell's own moment is past: nothing sent"
  assert !creature_unit_state.blocks_hostile(state:, now_ms: 14_500)
  let #(_, later) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 20_000,
    )
  assert later == [] as "an end long past: nothing sent either"
  let #(_, none) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [],
      went_at_ms: go_ms,
      now_ms: go_ms,
    )
  assert none == [] as "no rows, no hold"
}

pub fn the_timer_fire_ends_only_the_due_rows_and_rearms_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell 4178 holds states 6 and 13 at once: here for 2000 and 5000 ms.
  let #(state, held) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [
        Row(state: 6, delay_ms: 0, duration_ms: 2000),
        Row(state: 13, delay_ms: 0, duration_ms: 5000),
      ],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  assert held
    == [
      ToViewers(news: UnitStateHeld(state: 6, number: 1)),
      ToViewers(news: UnitStateHeld(state: 13, number: 2)),
      StartTimer(after_ms: 1900),
    ]
    as "the rows are told in row order, with one timer for the earliest end, 8000"
  let #(early, not_due) = creature_unit_state.ended(state:, now_ms: 7000)
  assert not_due == [StartTimer(after_ms: 1000)]
    as "a fire before any end drops nothing and sets the timer for the same end again"
  let #(state, first) = creature_unit_state.ended(state: early, now_ms: 8000)
  assert first
    == [
      ToViewers(news: UnitStateEnded(number: 1)),
      StartTimer(after_ms: 3000),
    ]
    as "the first ends by its own number; the timer is for the next end, 11 000"
  let #(state, second) = creature_unit_state.ended(state:, now_ms: 11_000)
  assert second == [ToViewers(news: UnitStateEnded(number: 2))]
    as "the last ends and no timer is set"
  assert !creature_unit_state.blocks_hostile(state:, now_ms: 11_000)
  let #(_, stale) = creature_unit_state.ended(state:, now_ms: 12_000)
  assert stale == [] as "a fire with nothing held does nothing"
}

pub fn two_casters_hold_one_state_by_two_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  // A first caster's go at 6000 holds state 6 for 8500 ms (to 14 500); a second caster's go
  // at 7000 holds it for 3000 ms (to 10 000).
  let #(state, first) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  assert first
    == [
      ToViewers(news: UnitStateHeld(state: 6, number: 1)),
      StartTimer(after_ms: 8400),
    ]
  let #(state, second) =
    creature_unit_state.set(
      state:,
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 3000)],
      went_at_ms: 7000,
      now_ms: 7100,
    )
  assert second
    == [
      ToViewers(news: UnitStateHeld(state: 6, number: 2)),
      CancelTimer,
      StartTimer(after_ms: 2900),
    ]
    as "a second hold under its own number; the running timer is cancelled before the earlier end is set"
  let #(state, ended_second) = creature_unit_state.ended(state:, now_ms: 10_000)
  assert ended_second
    == [
      ToViewers(news: UnitStateEnded(number: 2)),
      StartTimer(after_ms: 4500),
    ]
    as "the second ends by its number"
  assert creature_unit_state.blocks_hostile(state:, now_ms: 10_000)
    as "the first hold still blocks"
  let #(state, ended_first) = creature_unit_state.ended(state:, now_ms: 14_500)
  assert ended_first == [ToViewers(news: UnitStateEnded(number: 1))]
  assert !creature_unit_state.blocks_hostile(state:, now_ms: 14_500)
    as "no hold, no block"
}

pub fn a_later_hold_with_a_later_end_leaves_the_running_timer_alone_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 3000)],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  let #(_, later) =
    creature_unit_state.set(
      state:,
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 6200,
    )
  assert later == [ToViewers(news: UnitStateHeld(state: 6, number: 2))]
    as "the timer already runs for the earlier end, so none is asked: a timer id that runs cannot be started"
}

pub fn a_death_clears_the_states_and_cancels_the_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  let #(cleared, effects) = creature_unit_state.cleared(state:)
  assert effects == [CancelTimer]
    as "the timer is cancelled and no UnitStateEnded is told"
  assert !creature_unit_state.blocks_hostile(state: cleared, now_ms: 6200)
  let #(_, stale) = creature_unit_state.ended(state: cleared, now_ms: 14_500)
  assert stale == [] as "a fire already queued at the clear finds nothing"
  let #(_, again) = creature_unit_state.cleared(state: cleared)
  assert again == [] as "a creature that holds none has no timer to cancel"
}

pub fn a_hold_past_its_end_blocks_nothing_and_is_not_shown_before_its_timer_fires_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [Row(state: 6, delay_ms: 0, duration_ms: 8500)],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  assert creature_unit_state.shown(state:, now_ms: 14_499)
    == [UnitStateHeld(state: 6, number: 1)]
  assert creature_unit_state.shown(state:, now_ms: 14_500) == []
    as "a viewer arriving after the end but before the timer is told nothing"
  assert !creature_unit_state.blocks_hostile(state:, now_ms: 14_500)
}

pub fn a_viewer_is_shown_each_running_hold_in_the_order_they_began_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    creature_unit_state.set(
      state: creature_unit_state.new(),
      rows: [
        Row(state: 6, delay_ms: 0, duration_ms: 2000),
        Row(state: 13, delay_ms: 0, duration_ms: 5000),
      ],
      went_at_ms: go_ms,
      now_ms: 6100,
    )
  assert creature_unit_state.shown(state:, now_ms: 6200)
    == [
      UnitStateHeld(state: 6, number: 1),
      UnitStateHeld(state: 13, number: 2),
    ]
  let #(state, _) = creature_unit_state.ended(state:, now_ms: 8000)
  assert creature_unit_state.shown(state:, now_ms: 8000)
    == [UnitStateHeld(state: 13, number: 2)]
    as "an ended hold is not shown"
}
