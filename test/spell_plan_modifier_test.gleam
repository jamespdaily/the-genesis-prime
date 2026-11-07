//// The property modifiers of the plan (`genesis_prime/game/spell_plan`
//// `PropertyModifier`, `genesis_prime/game/effect_kind`). Expected values come from
//// these places:
//// - `Spell4Effects.effectType.11.change`: a type 11 row names its property in
////   dataBits00, its mode in dataBits01, its multiplier in dataBits02, its flat amount
////   in dataBits03 and its amount for each level in dataBits04, each a 32-bit float;
////   the kit's rows are 135954 (property 102, mode 3, 1.0, 0.0799999982 = 0x3da3d70a,
////   8000 ms, aimed at the caster) and 67777 (property 134, mode 3, 0.0, 0.0, delay 180,
////   duration 400), from `table_rows -- Spell4Effects effectType=11`.
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the
////   area; the rows aimed at the caster are read (12,603 of 20,105), and the 7,502
////   aimed only at others are the next step's, so they are not in the plan.
//// - The table columns are signed 32-bit integers (`game_table.column_type`), so a
////   float's bits above 0x7FFFFFFF arrive negative: -1.0, 0xBF800000, is -1082130432.
//// - The load's rules: a property no UnitProperty2 row names, and a coefficient that is
////   an infinity or not a number, fail the load.

import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{Always, GatedOnCaster, GatedOnTarget}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
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

/// 1.0 and 0.08 as the client's rows hold them (`table_rows -- Spell4Effects 135954`).
const one = 1_065_353_216

const point_zero_eight = 1_034_147_594

/// A type 11 row of a planted spell aimed by `target_flags`, in every phase, with these
/// columns beside its id, spell and type.
fn modifier_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(11)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
    #("dataBits00", Integer(102)),
    #("dataBits01", Integer(3)),
    #("dataBits02", Integer(one)),
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

fn modifiers_of(row row: List(Cell)) -> List(spell_plan.PropertyModifier) {
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
  spell.modifiers
}

fn plan_error(row row: List(Cell)) -> spell_plan.PlanError {
  let assert Error(error) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the build fails"
  error
}

// ---- the rows of the plan ----

pub fn a_row_aimed_at_the_caster_is_read_with_its_columns_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of the kit's 135954 as the client holds it (property 102, mode 3, 1.0, 0.08,
  // 8 s), planted under an id no client row holds.
  assert modifiers_of(
      row: modifier_row(id: 99_051, target_flags: 1, columns: [
        #("dataBits03", Integer(point_zero_eight)),
        #("durationTime", Integer(8000)),
      ]),
    )
    == [
      spell_plan.PropertyModifier(
        effect_id: Spell4EffectsId(99_051),
        phase_flags: -1,
        change: spell_plan.PropertyChange(Change(
          property: UnitProperty2Id(102),
          mode: 3,
          multiplier: 1.0,
          flat: 0.07999999821186066,
          per_level: 0.0,
        )),
        row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
        condition: Always,
        tag: spend.EqualTo(value: 0),
        armor: None,
      ),
    ]
    as "0x3da3d70a is 0.07999999821186066; the row's emmComparison 0 and emmValue 0 are the tag"
}

pub fn gates_falling_damage_row_is_read_with_its_delay_and_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of 67777 (FallingDamageMultiplier 134, multiplier 0.0, flat 0.0, delay 180,
  // 400 ms), planted under an id no client row holds.
  let assert [row] =
    modifiers_of(
      row: modifier_row(id: 99_052, target_flags: 1, columns: [
        #("dataBits00", Integer(134)),
        #("dataBits02", Integer(0)),
        #("delayTime", Integer(180)),
        #("durationTime", Integer(400)),
      ]),
    )
  assert row.change
    == spell_plan.PropertyChange(Change(
      property: UnitProperty2Id(134),
      mode: 3,
      multiplier: 0.0,
      flat: 0.0,
      per_level: 0.0,
    ))
  assert row.row
    == LastingRow(delay_ms: 180, duration_ms: 400, until_removed: False)
}

pub fn a_negative_multiplier_and_amounts_are_read_from_their_signed_bits_test() -> Nil {
  use <- owned_test.run(60_000)
  // -1.0 is 0xBF800000, -1082130432 as a signed column; -2.5 is 0xC0200000 and 35.0 is
  // 0x420C0000.
  let assert [row] =
    modifiers_of(
      row: modifier_row(id: 99_040, target_flags: 1, columns: [
        #("dataBits02", Integer(-1_082_130_432)),
        #("dataBits03", Integer(-1_071_644_672)),
        #("dataBits04", Integer(1_108_082_688)),
      ]),
    )
  let assert spell_plan.PropertyChange(Change(
    multiplier:,
    flat:,
    per_level:,
    ..,
  )) = row.change
  assert multiplier == -1.0
  assert flat == -2.5
  assert per_level == 35.0
}

pub fn a_coefficient_that_is_an_infinity_or_not_a_number_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x7F800000 is +infinity, 0x7FC00000 a NaN and 0xFF800000 -infinity.
  assert plan_error(
      row: modifier_row(id: 99_041, target_flags: 1, columns: [
        #("dataBits02", Integer(2_139_095_040)),
      ]),
    )
    == spell_plan.ModifierNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_041,
      column: "dataBits02",
    )
  assert plan_error(
      row: modifier_row(id: 99_042, target_flags: 1, columns: [
        #("dataBits03", Integer(2_143_289_344)),
      ]),
    )
    == spell_plan.ModifierNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_042,
      column: "dataBits03",
    )
  assert plan_error(
      row: modifier_row(id: 99_043, target_flags: 1, columns: [
        #("dataBits04", Integer(-8_388_608)),
      ]),
    )
    == spell_plan.ModifierNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_043,
      column: "dataBits04",
    )
}

pub fn a_row_that_names_a_property_with_no_unitproperty2_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      row: modifier_row(id: 99_044, target_flags: 1, columns: [
        #("dataBits00", Integer(200)),
      ]),
    )
    == spell_plan.ModifierPropertyHasNoRow(
      spell4_id: strike,
      effect_id: 99_044,
      property: 200,
    )
}

pub fn a_row_aimed_only_at_other_units_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // The next step reads them: 2 the primary target, 4 the area, 6 both.
  list.each([2, 4, 6], fn(flags) {
    assert modifiers_of(
        row: modifier_row(id: 99_045, target_flags: flags, columns: []),
      )
      == []
      as "a row aimed only at others is left out of the plan"
  })
}

pub fn a_row_aimed_at_the_caster_and_others_is_read_for_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3, 5 and 7 include the caster (449 rows): the caster's part is read, the rest is
  // not applied.
  list.each([3, 5, 7], fn(flags) {
    let assert [row] =
      modifiers_of(
        row: modifier_row(id: 99_046, target_flags: flags, columns: []),
      )
    assert row.effect_id == Spell4EffectsId(99_046)
  })
}

pub fn a_row_with_flags_bit_2_lasts_until_removed_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [row] =
    modifiers_of(
      row: modifier_row(id: 99_047, target_flags: 1, columns: [
        #("flags", Integer(2)),
      ]),
    )
  assert row.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
}

pub fn a_row_behind_a_caster_prerequisite_is_gated_on_the_caster_and_behind_a_target_one_is_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [caster] =
    modifiers_of(
      row: modifier_row(id: 99_048, target_flags: 1, columns: [
        #("prerequisiteIdCasterApply", Integer(17_302)),
      ]),
    )
  let assert GatedOnCaster(gates: [_]) = caster.condition
  let assert [target] =
    modifiers_of(
      row: modifier_row(id: 99_049, target_flags: 1, columns: [
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
        effect: modifier_row(id: 99_050, target_flags: 1, columns: [
          #("phaseFlags", Integer(2)),
        ]),
      ),
    )
  assert spell_plan.modifiers_in_phase(spell:, phase: 0, spent: None) == []
  assert list.length(spell_plan.modifiers_in_phase(
      spell:,
      phase: 1,
      spent: None,
    ))
    == 1
}

// ---- the effect kind ----

pub fn type_11_is_read_for_the_rows_that_include_the_caster_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 11) == effect_kind.PropertyModifier
  assert effect_kind.is_read(effect_type: 11)
  list.each([1, 3, 5, 7], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 11, target_flags: flags)
      as "bit 1 of targetFlags is the caster"
  })
  list.each([2, 4, 6], fn(flags) {
    assert !effect_kind.is_row_read(effect_type: 11, target_flags: flags)
      as "a row aimed only at others is the next step's"
  })
  assert effect_kind.is_row_read(effect_type: 17, target_flags: 2)
    as "every other type read is read for any aim"
  assert !effect_kind.is_row_read(effect_type: 90, target_flags: 1)
    as "an unread type stays unread"
}

// ---- the client's own rows ----

pub fn the_kits_two_rows_are_read_from_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  // Gate, 20325, whose own spell 34355 holds 67777.
  let assert Ok(gate) = spell_plan.in_plans(plans:, base: Spell4BaseId(20_325))
  let assert [falling] = gate.modifiers
  assert falling.effect_id == Spell4EffectsId(99_052)
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
  // Mind Burst, 19019, starts 57030 as a child, whose row 135954 raises BaseCritChance
  // by 0.08 for 8 s.
  let assert Ok(mind_burst) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(19_019))
  let assert Ok(proxy) =
    list.find(mind_burst.proxies, fn(proxy) {
      proxy.spell.spell4_id == Spell4Id(57_030)
    })
  let assert [crit] = proxy.spell.modifiers
  assert crit.effect_id == Spell4EffectsId(99_051)
  assert crit.change
    == spell_plan.PropertyChange(Change(
      property: UnitProperty2Id(102),
      mode: 3,
      multiplier: 1.0,
      flat: 0.07999999821186066,
      per_level: 0.0,
    ))
  assert crit.row
    == LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False)
}
