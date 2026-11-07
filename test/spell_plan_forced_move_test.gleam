//// The forced moves of the plan (`genesis_prime/game/spell_plan` `ForcedMove`,
//// `genesis_prime/game/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.3`: the kit's one row is 67776 (Gate's blink: delay
////   200 ms, phaseFlags 1, aimed at the caster), from
////   `table_rows -- Spell4Effects 67776`, and its spell 34355 also holds 67777.
//// - `Spell4Effects.effectType.3.player`: the client moves its own unit for a row aimed
////   at the caster, so the plan reads those rows and leaves out one aimed only at
////   others, which the server's 0x638 would carry (the next step).
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the
////   area.

import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{Always, GatedOnCaster, GatedOnTarget}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, UnitProperty2Id,
}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4 and base, whose tree the planted rows hold
/// (`spell_tables`).
const strike = 32_893

/// A type 3 row of a planted spell aimed by `target_flags`, in every phase, as Gate's
/// 67776 is but for its phase, with these columns beside its id, spell and type.
fn forced_move_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(3)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
  ]
  planted_table.row(
    spell4_effects.schema,
    list.append(
      list.filter(defaults, fn(default) {
        !list.any(columns, fn(given) { given.0 == default.0 })
      }),
      columns,
    ),
  )
}

fn forced_moves_of(row row: List(Cell)) -> List(spell_plan.ForcedMove) {
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
  spell.forced_moves
}

// ---- the rows of the plan ----

pub fn gates_row_aimed_at_the_caster_is_read_with_its_columns_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of 67776 as the client holds it (delay 200, phase flags 1), planted under
  // an id no client row holds.
  assert forced_moves_of(
      row: forced_move_row(id: 99_068, target_flags: 1, columns: [
        #("delayTime", Integer(200)),
        #("phaseFlags", Integer(1)),
      ]),
    )
    == [
      spell_plan.ForcedMove(
        effect_id: Spell4EffectsId(99_068),
        phase_flags: 1,
        delay_ms: 200,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the row's emmComparison 0 and emmValue 0 are the tag"
}

pub fn a_row_aimed_only_at_other_units_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // The next step moves them by 0x638: 2 the primary target, 4 the area, 6 both.
  list.each([2, 4, 6], fn(flags) {
    assert forced_moves_of(
        row: forced_move_row(id: 99_061, target_flags: flags, columns: []),
      )
      == []
      as "a row aimed only at others is left out of the plan"
  })
}

pub fn a_row_aimed_at_the_caster_and_others_is_read_for_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3, 5 and 7 include the caster: its part is read, the rest is not applied.
  list.each([3, 5, 7], fn(flags) {
    let assert [row] =
      forced_moves_of(
        row: forced_move_row(id: 99_062, target_flags: flags, columns: []),
      )
    assert row.effect_id == Spell4EffectsId(99_062)
  })
}

pub fn a_row_behind_a_caster_prerequisite_is_gated_on_the_caster_and_behind_a_target_one_is_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [caster] =
    forced_moves_of(
      row: forced_move_row(id: 99_065, target_flags: 1, columns: [
        #("prerequisiteIdCasterApply", Integer(17_302)),
      ]),
    )
  let assert GatedOnCaster(gates: [_]) = caster.condition
  let assert [target] =
    forced_moves_of(
      row: forced_move_row(id: 99_066, target_flags: 1, columns: [
        #("prerequisiteIdTargetApply", Integer(5)),
      ]),
    )
  assert target.condition == GatedOnTarget(prerequisite_id: PrerequisiteId(5))
}

pub fn the_rows_of_a_phase_are_those_whose_phase_flags_name_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // phaseFlags bit n is phase n (`Spell4Effects.phaseFlags`).
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: forced_move_row(id: 99_067, target_flags: 1, columns: [
          #("phaseFlags", Integer(2)),
        ]),
      ),
    )
  assert spell_plan.forced_moves_in_phase(spell:, phase: 0, spent: None) == []
  assert list.length(spell_plan.forced_moves_in_phase(
      spell:,
      phase: 1,
      spent: None,
    ))
    == 1
}

// ---- the effect kind ----

pub fn type_3_is_read_for_the_rows_that_include_the_caster_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 3) == effect_kind.ForcedMove
  assert effect_kind.is_read(effect_type: 3)
  list.each([1, 3, 5, 7], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 3, target_flags: flags)
      as "bit 1 of targetFlags is the caster"
  })
  list.each([2, 4, 6], fn(flags) {
    assert !effect_kind.is_row_read(effect_type: 3, target_flags: flags)
      as "a row aimed only at others is the next step's"
  })
  assert effect_kind.is_row_read(effect_type: 11, target_flags: 1)
    && !effect_kind.is_row_read(effect_type: 11, target_flags: 2)
    as "type 11 keeps its own reading"
  assert !effect_kind.is_row_read(effect_type: 90, target_flags: 1)
    as "an unread type stays unread"
}

// ---- the client's own rows ----

pub fn gates_two_caster_rows_are_read_from_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  // Gate, 20325, whose own spell 34355 holds 67776 and 67777.
  let assert Ok(gate) = spell_plan.in_plans(plans:, base: Spell4BaseId(20_325))
  assert gate.forced_moves
    == [
      spell_plan.ForcedMove(
        effect_id: Spell4EffectsId(67_776),
        phase_flags: 1,
        delay_ms: 200,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
  let assert [falling] = gate.modifiers
  assert falling.effect_id == Spell4EffectsId(67_777)
  assert falling.change
    == spell_plan.PropertyChange(Change(
      property: UnitProperty2Id(134),
      mode: 3,
      multiplier: 0.0,
      flat: 0.0,
      per_level: 0.0,
    ))
  assert falling.row
    == LastingRow(delay_ms: 180, duration_ms: 400, until_removed: False)
}
