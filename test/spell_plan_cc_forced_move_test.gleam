//// The move a Knockback, Pushback or Pull state throws its creature by
//// (`genesis_prime/game/spell_plan` `CrowdControl.move`). The state row names a
//// CCStateAdditionalData row in dataBits07, whose dataInt00 is a helper spell; the move is
//// that spell's own ForcedMove row (`table_rows -- CCStateAdditionalData 21`,
//// `table_rows -- Spell4Effects 73826`). Expected values come from these client rows.
//// - Spell4Effects 56250 (spell 30693): a Knockback state, dataBits07 21; CCStateAdditionalData 21:
////   ccStatesId 16, dataInt00 36010; Spell4Effects 73826 (spell 36010): effectType 3,
////   targetFlags 2, dataBits00 4 (kind 4: away from the reference unit, in flight),
////   dataBits01 and dataBits02 0x41200000 (10.0), dataBits03 375, dataBits04 0, dataBits05 1,
////   dataBits06 0x40000000 (2.0).
//// - Spell 75272 holds its own type 3 row (195749, targetFlags 4, dataBits00 3) and a Pull
////   state (196112, dataBits07 296): the spell moves its creature once, by its own row.
//// - Spell4Effects 82387 (spell 38426) names CCStateAdditionalData 83, which the table does
////   not hold; 56566 (spell 30815) is a Knockback with dataBits07 0. A PositionSwitch (state
////   19) or any other state is a state alone, whatever its dataBits07 names.
//// The whole-table counts are what `table_rows` counts over the client's tables.

import client_tables
import fixture_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/effect_row_read
import genesis_prime/game/forced_move
import genesis_prime/game/spell_plan
import genesis_prime/message/crowd_control_state.{
  type CrowdControlState, Knockback, PositionSwitch, Pull, Pushback,
}
import genesis_prime/table/cc_state_additional_data
import genesis_prime/table/id.{CCStateAdditionalDataId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

/// The spells that hold a state naming a helper and a type 3 row of their own aimed past
/// the caster, from the client's tables: each moves its creature once, by its own row.
const holding_both = [
  34_578, 35_550, 35_564, 35_618, 35_624, 40_695, 48_120, 48_124, 48_125, 48_133,
  48_137, 48_138, 55_043, 56_522, 66_001, 66_002, 75_272, 82_476, 82_477, 82_478,
]

/// The crowd-control rows of a spell planned alone.
fn controls_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(List(spell_plan.CrowdControl), spell_plan.PlanError) {
  spell_tables.planned_alone(tables:, spell4_id:)
  |> result.map(spell_plan.payloads(_, as_kind: spell_plan.as_control))
}

fn control_by_effect(
  controls controls: List(spell_plan.CrowdControl),
  effect_id effect_id: Int,
) -> spell_plan.CrowdControl {
  let assert Ok(control) =
    list.find(controls, fn(control) { control.effect_id.value == effect_id })
    as "the spell plans the state row"
  control
}

pub fn a_knockback_state_names_its_helpers_move_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let assert Ok(controls) = controls_of(tables:, spell4_id: 30_693)
    as "the spell with a Knockback state loads"
  let control = control_by_effect(controls:, effect_id: 56_250)
  assert control.row.state == Knockback
  assert control.move
    == Some(forced_move.Move(
      way: forced_move.Away,
      mover: forced_move.Flight,
      min_distance: 10.0,
      max_distance: 10.0,
      flight_ms: 375,
      gravity: 0.0,
      flags: 1,
      height: 2.0,
    ))
    as "the state throws by Spell4Effects 73826, which CCStateAdditionalData 21 names as helper 36010: away, in flight, 10.0 to 10.0, 375 ms, no gravity, flags 1, height 2.0"
}

pub fn a_missing_helper_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // CCStateAdditionalData 21 is edited to name spell 36272 (a PositionSwitch spell), which
  // holds no type 3 row: no client row names such a helper, so the case is edited in.
  fixture_tables.changed(
    table: "CCStateAdditionalData",
    id: 21,
    with: [#("dataInt00", Integer(36_272))],
    body: fn(tables) {
      assert controls_of(tables:, spell4_id: 30_693)
        == Error(spell_plan.ControlHelperNotRead(
          spell4_id: 30_693,
          effect_id: 56_250,
          helper: 36_272,
        ))
        as "the state's helper holds no ForcedMove row, so its move is unknown and the spell fails to load"
    },
  )
  let tables = fixture_tables.shared()
  let assert Ok(absent) = controls_of(tables:, spell4_id: 38_426)
    as "a state that names a CCStateAdditionalData row the table lacks (83) is a state alone"
  assert control_by_effect(controls: absent, effect_id: 82_387).move == None
    as "the client's row 82387 names an absent row, so the state carries no move"
  let assert Ok(zero) = controls_of(tables:, spell4_id: 30_815)
    as "a Knockback with dataBits07 0 loads"
  assert control_by_effect(controls: zero, effect_id: 56_566).move == None
    as "dataBits07 0 names no helper"
}

pub fn a_helper_aimed_at_the_caster_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 73826, the helper move of Spell4Effects 56250 (spell 30693), has
  // targetFlags 2. No client row aims a helper at the caster alone, so the case is edited in.
  fixture_tables.changed(
    table: "Spell4Effects",
    id: 73_826,
    with: [#("targetFlags", Integer(1))],
    body: fn(tables) {
      assert controls_of(tables:, spell4_id: 30_693)
        == Error(spell_plan.ControlHelperNotRead(
          spell4_id: 30_693,
          effect_id: 56_250,
          helper: 36_010,
        ))
        as "a helper move aimed at the caster alone moves the caster's own unit, not the creature the state holds, so the spell fails to load"
    },
  )
  // Aimed at the area, or the primary target and the area, the helper moves the units a
  // strike hits (`Spell4Effects.effectType.3.other_unit`).
  list.each([4, 6], fn(target_flags) {
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 73_826,
      with: [#("targetFlags", Integer(target_flags))],
      body: fn(tables) {
        let assert Ok(controls) = controls_of(tables:, spell4_id: 30_693)
          as "a helper aimed at units a strike hits loads"
        assert option.is_some(
          control_by_effect(controls:, effect_id: 56_250).move,
        )
          as "the state carries the helper's move"
      },
    )
  })
}

pub fn a_spell_holding_its_own_throw_drops_the_states_helper_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let assert Ok(spell) =
    spell_plan.spell_alone(tables:, sources:, spell4_id: 75_272, chain: [])
    as "spell 75272 loads"
  let thrown = spell_plan.payloads(spell:, as_kind: spell_plan.as_struck_move)
  assert list.map(thrown, fn(throw) { throw.effect_id.value }) == [195_749]
    as "the spell has one move, by its own type 3 row 195749"
  assert list.map(thrown, fn(throw) { throw.move.way }) == [forced_move.Toward]
    as "row 195749 has dataBits00 3, a kind that moves toward the reference unit"
  let controls = spell_plan.payloads(spell:, as_kind: spell_plan.as_control)
  let pull = control_by_effect(controls:, effect_id: 196_112)
  assert pull.row.state == Pull
  assert pull.move == None
    as "the Pull state's helper (CCStateAdditionalData 296) is dropped, so the creature moves once"
}

/// Whether a state is one a helper's move throws a creature by.
fn throws(state state: CrowdControlState) -> Bool {
  state == Knockback || state == Pushback || state == Pull
}

/// A state row the plan reads as a spell that throws by its own row (`own_throw`) or does
/// not, as the plan of its spell reads it.
fn read_state_row(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  place_of place_of: fn(Int) -> spell_plan.RowPlace,
  row row: Spell4Effects,
  own_throw own_throw: Bool,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  spell_plan.read_row(
    tables:,
    sources:,
    place: spell_plan.RowPlace(
      ..place_of(row.spell_id),
      throws_target: own_throw || place_of(row.spell_id).throws_target,
    ),
    effect: row,
  )
}

pub fn a_state_that_is_not_a_throw_ignores_the_helper_it_names_test() -> Nil {
  use <- owned_test.run(60_000)
  // No client PositionSwitch row names a throw helper, so the case is edited in: the
  // Knockback state 56250 (dataBits07 21, helper 36010) takes each state in turn.
  list.each([19, 8, 12], fn(state) {
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 56_250,
      with: [#("dataBits00", Integer(state))],
      body: fn(tables) {
        let assert Ok(controls) = controls_of(tables:, spell4_id: 30_693)
          as "the spell loads with the edited state"
        let control = control_by_effect(controls:, effect_id: 56_250)
        assert control.row.state == crowd_control_state.from_value(state)
          as "the row holds the edited state"
        assert control.move == None
          as "a state other than Knockback, Pushback or Pull throws nothing, whatever helper its dataBits07 names"
      },
    )
  })
}

pub fn a_position_switch_state_carries_no_move_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let effects = spell4_effects.all(tables)
  let place_of = effect_row_read.places(tables:, effects:)
  let sources = spell_plan.sources_of(tables:)
  let states =
    list.filter(effects, fn(effect) {
      effect_kind.kind_of(effect.effect_type) == effect_kind.CrowdControl
    })
  let state_of = fn(row: Spell4Effects) {
    crowd_control_state.from_value(row.data_bits00)
  }
  let switches =
    list.filter(states, fn(row) { state_of(row) == PositionSwitch })
  let other_states_naming_a_throw =
    list.filter(states, fn(row) {
      case additional_of(tables:, row:) {
        Ok(additional) ->
          row.data_bits07 != 0
          && !throws(state: state_of(row))
          && throws(state: crowd_control_state.from_value(
            additional.cc_states_id,
          ))
        Error(Nil) -> False
      }
    })
  assert list.length(switches) == 20
    as "the client holds 20 PositionSwitch rows"
  assert list.map(other_states_naming_a_throw, fn(row) { row.id })
    == [
      81_004, 87_069, 87_882, 95_683, 102_854, 102_856, 104_404, 107_442,
      133_825, 220_582, 220_638,
    ]
    as "eleven rows of a state other than a throw name a CCStateAdditionalData row of Knockback, Pushback or Pull"
  list.each(list.append(switches, other_states_naming_a_throw), fn(row) {
    let reading =
      read_state_row(tables:, sources:, place_of:, row:, own_throw: False)
    // Rows 102854, 102856 and 104404 are refused for another unread prerequisite before
    // any helper is consulted; a refusal for the helper would be the fault.
    assert !refused_for_its_helper(reading:)
      as "the plan does not consult a helper for a state other than Knockback, Pushback or Pull"
    let move =
      result.map(reading, fn(read) { control_read(reading: read).move })
    assert result.unwrap(move, None) == None
      as "only a Knockback, Pushback or Pull state throws its creature: any other state is a state alone, whatever its dataBits07 names"
  })
}

/// Whether the plan refused a state row for its helper spell's rows.
fn refused_for_its_helper(
  reading reading: Result(spell_plan.RowReading, spell_plan.PlanError),
) -> Bool {
  case reading {
    Error(spell_plan.ControlHelperNotRead(..)) -> True
    _ -> False
  }
}

/// The client's rows of a Knockback, Pushback or Pull state whose dataBits07 is not 0.
fn state_rows(effects effects: List(Spell4Effects)) -> List(Spell4Effects) {
  list.filter(effects, fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.CrowdControl
    && throws(state: crowd_control_state.from_value(effect.data_bits00))
    && effect.data_bits07 != 0
  })
}

/// The CCStateAdditionalData row a state row names, when the table holds it.
fn additional_of(
  tables tables: table_store.Tables,
  row row: Spell4Effects,
) -> Result(cc_state_additional_data.CCStateAdditionalData, Nil) {
  cc_state_additional_data.get(
    tables:,
    id: CCStateAdditionalDataId(row.data_bits07),
  )
}

pub fn every_knockback_pull_and_pushback_row_names_a_helper_with_a_throw_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let effects = spell4_effects.all(tables)
  let rows = state_rows(effects:)
  let #(named, absent) =
    list.partition(rows, fn(row) { result.is_ok(additional_of(tables:, row:)) })
  assert list.map(absent, fn(row) { row.id }) == [82_387]
    as "effect 82387 (spell 38426, CCStateAdditionalData 83) is the only state row that names a row the table lacks"
  assert list.length(named) == 469 as "the client holds 469 helper-bearing rows"
  let count = fn(state) {
    list.count(named, fn(row) {
      crowd_control_state.from_value(row.data_bits00) == state
    })
  }
  assert [count(Knockback), count(Pushback), count(Pull)] == [362, 47, 60]
    as "362 Knockback, 47 Pushback and 60 Pull rows"
  let place_of = effect_row_read.places(tables:, effects:)
  let sources = spell_plan.sources_of(tables:)
  let read = fn(row: Spell4Effects, own_throw: Bool) {
    read_state_row(tables:, sources:, place_of:, row:, own_throw:)
  }
  let readings = list.map(rows, fn(row) { #(row, read(row, False)) })
  let refused = list.filter(readings, fn(entry) { result.is_error(entry.1) })
  // The plan refuses 50 of these rows for an apply prerequisite it does not read (types
  // 177, 102 and 196) or a target prerequisite that reads the struck unit (type 15),
  // before it reaches the helper: read as a spell that throws by its own row, which
  // never reads the helper, each is refused the same.
  assert list.length(refused) == 50
    as "50 state rows are refused for their prerequisites"
  list.each(refused, fn(entry) {
    assert read(entry.0, True) == entry.1
      as "a refused row is refused for its prerequisites, never for its helper"
  })
  list.each(named, fn(row) {
    let assert Ok(_) = helper_move(tables:, effects:, row:)
      as "the helper holds exactly one type 3 row, which is a move"
  })
  let both = set.from_list(holding_both)
  let read_ok =
    list.filter_map(readings, fn(entry) {
      result.map(entry.1, fn(reading) { #(entry.0, reading) })
    })
  list.each(read_ok, fn(entry) {
    let #(row, reading) = entry
    let control = control_read(reading:)
    case set.contains(both, row.spell_id) || row.id == 82_387 {
      True -> {
        assert control.move == None
          as "a spell that throws its creature by its own row, and a state naming an absent row, carry no move"
      }
      False -> {
        let assert Ok(move) = helper_move(tables:, effects:, row:)
        assert control.move == Some(move)
          as "the state carries the move of its helper's row"
      }
    }
  })
}

/// The one state a row the plan reads makes.
fn control_read(
  reading reading: spell_plan.RowReading,
) -> spell_plan.CrowdControl {
  let planned = case reading {
    spell_plan.Applied(spell_plan.ReadEffects(planned))
    | spell_plan.Held(spell_plan.ReadEffects(planned)) -> planned
    spell_plan.Applied(..)
    | spell_plan.Held(..)
    | spell_plan.LeftOut(..)
    | spell_plan.ReadByArea
    | spell_plan.ReadByActivation -> []
  }
  let assert [control] =
    list.filter_map(planned, fn(effect) { spell_plan.as_control(effect.kind) })
    as "every state row the plan reads is listed or held as one state"
  control
}

/// The move of the one type 3 row of the helper spell a state row names, or why it has
/// none.
fn helper_move(
  tables tables: table_store.Tables,
  effects effects: List(Spell4Effects),
  row row: Spell4Effects,
) -> Result(forced_move.Move, Nil) {
  use additional <- result.try(additional_of(tables:, row:))
  case
    list.filter(effects, fn(effect) {
      effect.spell_id == additional.data_int00
      && effect_kind.kind_of(effect.effect_type) == effect_kind.ForcedMove
    })
  {
    [helper_row] ->
      forced_move.of_row(row: helper_row) |> result.replace_error(Nil)
    [] | [_, _, ..] -> Error(Nil)
  }
}

pub fn exactly_twenty_spells_hold_both_a_helper_and_their_own_throw_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let effects = spell4_effects.all(tables)
  let with_helper =
    state_rows(effects:)
    |> list.filter(fn(row) { result.is_ok(additional_of(tables:, row:)) })
    |> list.map(fn(row) { row.spell_id })
    |> set.from_list
  let own = spell_plan.spells_that_throw_target(effects:)
  assert set.intersection(with_helper, own)
    |> set.to_list
    |> list.sort(int.compare)
    == holding_both
    as "twenty spells hold a helper-bearing state and a type 3 row aimed past the caster"
}
