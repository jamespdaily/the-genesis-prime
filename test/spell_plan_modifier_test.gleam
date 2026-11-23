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
////   area; the rows aimed at the caster are read for the caster (12,603 of 20,105), and
////   the 7,502 aimed only at others (2, 4 or 6) are read for the units a strike hits
////   (`StruckChange`); a row that includes the caster and others (3, 5, 7: 449 rows)
////   is read for the caster only. The rows 94370 (spell 41886, flags 2, property 160,
////   mode 2, dataBits02 0x3f8ccccd = 1.1, 8000 ms), 7711 (spell 671, flags 4, property
////   100, mode 2, 0x3f000000 = 0.5, delay 1000, 5000 ms, phaseFlags 1) and 184458
////   (spell 62709, flags 6, property 130, mode 1, 0x40600000 = 3.5, delay 1750,
////   1500 ms) are the shapes planted, from `table_rows -- Spell4Effects effectType=11`.
//// - The table columns are signed 32-bit integers (`game_table.column_type`), so a
////   float's bits above 0x7FFFFFFF arrive negative: -1.0, 0xBF800000, is -1082130432.
//// - The load's rules: a property no UnitProperty2 row names, and a coefficient that is
////   an infinity or not a number, fail the load.

import client_tables
import fixture_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{Always, GatedOnCaster, GatedOnTarget}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import genesis_prime/table/loader/store
import gleam/list
import gleam/option.{None}
import gleam/result
import owned_test
import planted_table.{type Cell, Float, Integer}
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
  spell_tables.effect_row_over(
    id:,
    effect_type: 11,
    target_flags:,
    defaults: [
      #("dataBits00", Integer(102)),
      #("dataBits01", Integer(3)),
      #("dataBits02", Integer(one)),
    ],
    columns:,
  )
}

fn modifiers_of(row row: List(Cell)) -> List(spell_plan.PropertyModifier) {
  spell_tables.planned_payloads(row:, as_kind: spell_plan.as_modifier)
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
  assert spell_tables.plan_error(
      row: modifier_row(id: 99_041, target_flags: 1, columns: [
        #("dataBits02", Integer(2_139_095_040)),
      ]),
    )
    == spell_plan.ModifierNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_041,
      column: "dataBits02",
    )
  assert spell_tables.plan_error(
      row: modifier_row(id: 99_042, target_flags: 1, columns: [
        #("dataBits03", Integer(2_143_289_344)),
      ]),
    )
    == spell_plan.ModifierNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_042,
      column: "dataBits03",
    )
  assert spell_tables.plan_error(
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
  assert spell_tables.plan_error(
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

pub fn row_aimed_at_struck_units_is_planned_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shapes of 94370 (2: the primary target), 7711 (4: the area) and 184458 (6: both),
  // planted under ids no client row holds.
  let shapes = [
    #(
      99_061,
      2,
      spell_plan.AimsAtPrimaryTarget,
      [
        #("dataBits00", Integer(160)),
        #("dataBits01", Integer(2)),
        #("dataBits02", Integer(1_066_192_077)),
        #("durationTime", Integer(8000)),
      ],
      -1,
      Change(
        property: UnitProperty2Id(160),
        mode: 2,
        multiplier: 1.100000023841858,
        flat: 0.0,
        per_level: 0.0,
      ),
      LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
    ),
    #(
      99_062,
      4,
      spell_plan.AimsAtArea,
      [
        #("dataBits00", Integer(100)),
        #("dataBits01", Integer(2)),
        #("dataBits02", Integer(1_056_964_608)),
        #("delayTime", Integer(1000)),
        #("durationTime", Integer(5000)),
        #("phaseFlags", Integer(1)),
      ],
      1,
      Change(
        property: UnitProperty2Id(100),
        mode: 2,
        multiplier: 0.5,
        flat: 0.0,
        per_level: 0.0,
      ),
      LastingRow(delay_ms: 1000, duration_ms: 5000, until_removed: False),
    ),
    #(
      99_063,
      6,
      spell_plan.AimsAtPrimaryTargetAndArea,
      [
        #("dataBits00", Integer(130)),
        #("dataBits01", Integer(1)),
        #("dataBits02", Integer(1_080_033_280)),
        #("delayTime", Integer(1750)),
        #("durationTime", Integer(1500)),
      ],
      -1,
      Change(
        property: UnitProperty2Id(130),
        mode: 1,
        multiplier: 3.5,
        flat: 0.0,
        per_level: 0.0,
      ),
      LastingRow(delay_ms: 1750, duration_ms: 1500, until_removed: False),
    ),
  ]
  list.each(shapes, fn(shape) {
    let #(id, flags, aim, columns, phase_flags, change, row) = shape
    assert modifiers_of(row: modifier_row(id:, target_flags: flags, columns:))
      == [
        spell_plan.PropertyModifier(
          effect_id: Spell4EffectsId(id),
          phase_flags:,
          change: spell_plan.StruckChange(modifier: change, aim:),
          row:,
          condition: Always,
          tag: spend.EqualTo(value: 0),
          armor: None,
        ),
      ]
      as "a row aimed only at others is planned for the units a strike hits"
  })
}

pub fn a_row_aimed_at_the_caster_and_others_is_read_for_the_caster_and_for_the_others_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3, 5 and 7 hold the caster's bit and others' (449 rows, `Spell4Effects.targetFlags`):
  // the row is two, the caster's change and the others' change (#794); the stacking of
  // casters' modifiers on one creature is not built (#569).
  let change =
    Change(
      property: UnitProperty2Id(102),
      mode: 3,
      multiplier: 1.0,
      flat: 0.0,
      per_level: 0.0,
    )
  list.each(
    [
      #(3, spell_plan.AimsAtPrimaryTarget),
      #(5, spell_plan.AimsAtArea),
      #(7, spell_plan.AimsAtPrimaryTargetAndArea),
    ],
    fn(shape) {
      let #(flags, past_the_caster) = shape
      let assert [caster_part, others_part] =
        modifiers_of(
          row: modifier_row(id: 99_046, target_flags: flags, columns: []),
        )
      assert caster_part.effect_id == Spell4EffectsId(99_046)
      assert caster_part.change == spell_plan.PropertyChange(change)
        as "the caster takes the row's change"
      assert others_part.effect_id == Spell4EffectsId(99_046)
      assert others_part.change
        == spell_plan.StruckChange(modifier: change, aim: past_the_caster)
        as "the units the flag's other bits name take the same change"
    },
  )
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
  let assert GatedOnTarget(prerequisite: gate) = target.condition
  assert prerequisite.id(prerequisite: gate) == PrerequisiteId(5)
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
  assert spell_plan.in_phase(
      spell:,
      phase: 0,
      spent: None,
      as_kind: spell_plan.as_modifier,
    )
    == []
  assert list.length(spell_plan.in_phase(
      spell:,
      phase: 1,
      spent: None,
      as_kind: spell_plan.as_modifier,
    ))
    == 1
}

// ---- the effect kind ----

pub fn type_11_is_read_for_the_rows_aimed_at_the_caster_or_struck_units_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 11) == effect_kind.PropertyModifier
  assert effect_kind.is_read(effect_type: 11)
  list.each([1, 2, 3, 4, 5, 6, 7], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 11, target_flags: flags)
      as "bit 1 of targetFlags is the caster, 2 and 4 the units a strike hits"
  })
  assert !effect_kind.is_row_read(effect_type: 11, target_flags: 0)
    as "a row aimed at nobody is not read"
  assert effect_kind.is_row_read(effect_type: 17, target_flags: 2)
    as "every other type read is read for any aim"
  assert !effect_kind.is_row_read(effect_type: 90, target_flags: 1)
    as "an unread type stays unread"
}

// ---- the client's own rows ----

pub fn a_modifier_row_with_a_parameter_factor_is_not_read_and_one_without_still_plans_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 86849's shape (`table_rows -- Spell4Effects 86849`): parameters 12, 13 and 10 with
  // factors. A parameter whose factor is 0.0 adds nothing to the amount, and a parameter
  // of type 0 names none (rows 128380 and 128381 hold a value of 0.1 with type 0), so
  // neither is a parameter the plan must read.
  let parameter = fn(slot, kind, value) {
    [
      #("parameterType0" <> slot, Integer(kind)),
      #("parameterValue0" <> slot, Float(value)),
    ]
  }
  let cases = [
    #("no parameter", 99_061, 1, [], Ok(Nil)),
    #(
      "a parameter type with no factor",
      99_062,
      1,
      parameter("0", 12, 0.0),
      Ok(Nil),
    ),
    #(
      "a value on parameter type 0, which names no parameter",
      99_067,
      1,
      parameter("0", 0, 0.1),
      Ok(Nil),
    ),
    #(
      "a stat parameter with a factor on the caster",
      99_063,
      1,
      parameter("0", 12, 0.19),
      Error(12),
    ),
    #(
      "a stat parameter with a factor on a struck unit",
      99_064,
      2,
      parameter("0", 12, 0.19),
      Error(12),
    ),
    #(
      "the first of two factors, with a zero factor before it",
      99_065,
      1,
      list.flatten([
        parameter("0", 12, 0.0),
        parameter("1", 13, 0.19),
        parameter("3", 10, 16.59),
      ]),
      Error(13),
    ),
    #(
      "a flat parameter with a factor",
      99_066,
      1,
      parameter("3", 10, 16.59),
      Error(10),
    ),
  ]
  list.each(cases, fn(case_) {
    let #(why, id, target_flags, columns, expected) = case_
    let planned =
      spell_tables.planned_strike(
        rows: spell_tables.rows_with_effect(effect: modifier_row(
          id:,
          target_flags:,
          columns:,
        )),
      )
    case expected {
      Ok(Nil) -> {
        assert result.is_ok(planned) as why
      }
      Error(parameter_kind) -> {
        assert planned
          == Error(spell_plan.ParameterNotRead(
            spell4_id: strike,
            effect_id: id,
            row: spell_plan.ModifierRow,
            parameter_kind:,
          ))
          as why
      }
    }
  })
}

pub fn the_kits_two_rows_are_read_from_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  // Gate, 20325, whose own spell 34355 holds 67777.
  let assert Ok(gate) = spell_plan.in_plans(plans:, base: Spell4BaseId(20_325))
  let assert [falling] =
    spell_plan.payloads(spell: gate, as_kind: spell_plan.as_modifier)
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
  // Mind Burst, 19019, starts 57030 as a child, whose row 135954 raises BaseCritChance
  // by 0.08 for 8 s.
  let assert Ok(mind_burst) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(19_019))
  let assert Ok(proxy) =
    list.find(
      spell_plan.payloads(spell: mind_burst, as_kind: spell_plan.as_proxy),
      fn(proxy) { proxy.spell.spell4_id == Spell4Id(57_030) },
    )
  let assert [crit] =
    spell_plan.payloads(spell: proxy.spell, as_kind: spell_plan.as_modifier)
  assert crit.effect_id == Spell4EffectsId(135_954)
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

/// Whether the plan of the Spell4 `spell4_id` on `tables` says its changes outlive their
/// caster's sight.
fn outlives_on(tables tables: store.Tables, spell4_id spell4_id: Int) -> Bool {
  let assert Ok(spell) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id:,
      chain: [],
    )
    as "the spell plans alone"
  spell.outlives_caster
}

pub fn a_spell_outlives_its_caster_when_its_propertyflags_hold_0x100_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client keeps a cast whose caster is removed when Spell4.propertyFlags has 0x100
  // (`cast.target_node_end`: the record flag `0x108 & 0x10`, built from propertyFlags 0x100
  // by `FillSpellRecord 0x140568540`). The columns are the table's own
  // (`table_rows -- Spell4 32823 32821 32893`): 257 and 8448 hold the bit, 0x4000002 does not.
  assert outlives_on(tables: fixture_tables.shared(), spell4_id: 32_823)
    as "Phantasmal Armor tier 1 (propertyFlags 257) outlives its caster"
  assert outlives_on(tables: fixture_tables.shared(), spell4_id: 32_821)
    as "Bolster (propertyFlags 8448 = 0x2100) outlives its caster"
  assert !outlives_on(tables: fixture_tables.shared(), spell4_id: strike)
    as "Telekinetic Strike (propertyFlags 0x4000002) does not"
}
