//// The Absorption rows of the plan (`genesis_prime/game/spell_plan`
//// `PropertyModifier.change` of `AbsorbChange`, `genesis_prime/game/effect_kind`).
//// Expected values come from these places.
//// - `Spell4Effects.effectType.29`: an Absorption row gives the unit it lands on a pool for
////   durationTime; dataBits00 is a float multiplier, dataBits01 a float flat amount
////   ('Granted 45 Absorb' is row 183643's 1110704128 = 45.0), dataBits04 the mask of the
////   damage types it takes, the parameters the stat part. Row 178144 (Esper Spectral Form
////   58586, `table_rows -- Spell4Effects spellId=58586`): targetFlags 1, damageType 3,
////   durationTime 5000, dataBits00 1065353216 (1.0), dataBits01 0, dataBits04 7,
////   parameterType00 12 and 01 13 with value 2.5309998989105225 (0x4021fbe7), phaseFlags 1.
////   Row 93774 (Esper Moxie's proc, Spell4 41714): targetFlags 2, damageType 3,
////   durationTime 5000, dataBits00 1.0, dataBits04 7, parameters of kinds 12, 13 and 10,
////   phaseFlags -1. Row 56356 (Spell4 30724): targetFlags 2, dataBits00 0, dataBits01
////   100.0, no parameter. Row 46247 (Spell4 27567): tickTime 1000, durationTime 6001,
////   targetFlags 1 (`table_rows -- Spell4Effects 93774 56356 46247`).
//// - `Spell4Effects.effectType.29`'s gaps: a periodic absorb's reading, an absorb with no
////   lifetime and an absorb on a struck unit are not known, so the load fails for them.
//// - `opcode.0x7f4.effect_time`: a row whose Spell4Effects flags have bit 2 never ends; 33
////   rows of duration 0 hold flags bit 2.
//// - `0x140565600`: the formula's parameter kinds the caster's value reads; 18 (the
////   passed-in value) is not read. Row 68969 (Water Shield - Pell Water, Spell4 34700):
////   targetFlags 1, delayTime 0, durationTime 10000, flags 0, dataBits00 1.0, dataBits01
////   0, parameterType00 4 (Magic, `0x140566d40` case 4) with value 5.0.
//// - `Spell4Effects.targetFlags`: bit 1 the caster, 2 the primary target, 4 the area. The
////   primary target of a cast on the caster is the caster; a child a Proxy starts on each
////   struck unit has that unit as its primary target.
//// - The type 11 precedent (`effect_kind.is_row_read`): a row aimed only at other units
////   is left out and counted as not read.
//// The rows are in memory except in the last test, which reads the client's tables.

import client_tables
import fixture_tables
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  Absorption, AimsAtCaster, AimsAtPrimaryTarget, Always,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/list
import gleam/option.{None}
import gleam/result
import owned_test
import planted_table.{type Cell, Float, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4, whose tree the planted rows hold (`spell_tables`).
const strike = 32_893

/// 1.0 as 32 float bits.
const one_as_float_bits = 1_065_353_216

/// 45.0 as 32 float bits (row 183643's dataBits01).
const forty_five_as_float_bits = 1_110_704_128

/// The columns of row 178144 other than its id, spell and aim.
fn spectral_form_columns() -> List(#(String, Cell)) {
  [
    #("damageType", Integer(3)),
    #("durationTime", Integer(5000)),
    #("dataBits00", Integer(one_as_float_bits)),
    #("dataBits04", Integer(7)),
    #("parameterType00", Integer(12)),
    #("parameterType01", Integer(13)),
    #("parameterValue00", Float(2.531)),
    #("parameterValue01", Float(2.531)),
    #("phaseFlags", Integer(1)),
  ]
}

/// The columns of a readable amount: dataBits00 1.0 and dataBits01 45.0 (row 183643's).
fn amount_columns() -> List(#(String, Cell)) {
  [
    #("dataBits00", Integer(one_as_float_bits)),
    #("dataBits01", Integer(forty_five_as_float_bits)),
  ]
}

/// A type 29 row of the planted spell aimed by `target_flags`, with these columns beside
/// its id, spell and type.
fn absorption_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  spell_tables.effect_row_with(id:, effect_type: 29, target_flags:, columns:)
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

/// The plan's reading of one row, whose tables the plan reads nothing from for a type 29
/// row.
fn modifier_of(
  spell4_id spell4_id: Int,
  effect effect: Spell4Effects,
) -> Result(spell_plan.PropertyModifier, spell_plan.PlanError) {
  spell_plan.modifier_of(
    tables: fixture_tables.shared(),
    spell4_id:,
    effect:,
    condition: Always,
  )
}

/// The Spell4Effects row of this id as the client holds it.
fn client_effect(id id: Int) -> Spell4Effects {
  let assert Ok(row) =
    spell4_effects.get(tables: fixture_tables.shared(), id: Spell4EffectsId(id))
    as "the client's rows hold the row"
  row
}

/// Row 178144 as the client holds it: Spectral Form's absorption.
fn spectral_form_row() -> Spell4Effects {
  client_effect(id: 178_144)
}

// ---- the rows of the plan ----

pub fn an_absorption_row_aimed_at_the_caster_is_read_with_its_formula_mask_and_time_test() -> Nil {
  use <- owned_test.run(60_000)
  assert modifiers_of(row: absorption_row(
      id: 99_061,
      target_flags: 1,
      columns: spectral_form_columns(),
    ))
    == [
      spell_plan.PropertyModifier(
        effect_id: Spell4EffectsId(99_061),
        phase_flags: 1,
        change: spell_plan.AbsorbChange(Absorption(
          formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
            Parameter(kind: 12, value: 2.5309998989105225),
            Parameter(kind: 13, value: 2.5309998989105225),
            Parameter(kind: 0, value: 0.0),
            Parameter(kind: 0, value: 0.0),
          ]),
          mask: 7,
          aim: AimsAtCaster,
        )),
        row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
        condition: Always,
        tag: spend.EqualTo(value: 0),
        armor: None,
      ),
    ]
    as "row 178144: kinds 12 and 13 x 2.531, dataBits00 1.0, dataBits01 0.0, mask 7, 5000 ms, phase 1"
}

pub fn an_absorption_rows_data_bits01_is_read_as_a_float_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 183643 (Spell4 71564): dataBits00 1.0, dataBits01 1110704128, text 581159
  // 'Granted 45 Absorb'.
  let row =
    Spell4Effects(
      ..spectral_form_row(),
      id: 183_643,
      spell_id: 71_564,
      data_bits01: forty_five_as_float_bits,
      parameter_type00: 0,
      parameter_type01: 0,
      parameter_value00: 0.0,
      parameter_value01: 0.0,
    )
  let assert Ok(read) = modifier_of(spell4_id: 71_564, effect: row)
  let assert spell_plan.AbsorbChange(absorption) = read.change
  assert absorption.formula.base == 45.0
    as "the bits 0x42340000 are 45.0, not the integer 1110704128"
  assert absorption.formula.multiplier == 1.0
}

pub fn an_absorption_row_aimed_at_the_primary_target_is_read_in_a_spell_cast_on_the_caster_and_fails_the_load_in_a_child_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 93774 of Esper Moxie's proc 41714 as the client holds it.
  let row = client_effect(id: 93_774)
  let assert Ok(read) = modifier_of(spell4_id: 41_714, effect: row)
  let assert spell_plan.AbsorbChange(absorption) = read.change
  assert absorption.aim == AimsAtPrimaryTarget
    as "targetFlags 2 is the primary target, which the target of a cast on the caster is"
  let on_each_struck =
    spell_tables.started_on_each_struck(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
    )
  assert spell_tables.read_row(effect: row, place: spell_tables.pressed)
    == Ok(spell_plan.Applied(spell_plan.PlannedModifier(read)))
    as "a spell a Proxy aimed at the caster starts, or a pressed one, is cast on the caster"
  assert spell_tables.read_row(effect: row, place: on_each_struck)
    == Error(spell_plan.AbsorptionOnStruckUnit(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
      effect_id: 93_774,
    ))
    as "the spell's primary target is a struck unit, and an absorb on one is not built"
  assert spell_tables.read_row(
      effect: Spell4Effects(..row, target_flags: 3),
      place: on_each_struck,
    )
    |> result.is_ok
    as "a row that includes the caster reaches the caster, whichever unit the spell is cast on"
  // The planted Telekinetic Strike holds Proxy 62204 aimed at the area (targetFlags 4),
  // which starts 30900 on each unit it strikes (`spell_tables`).
  assert plan_error(
      row: absorption_row(id: 99_060, target_flags: 2, columns: [
        #("spellId", Integer(30_900)),
        #("durationTime", Integer(5000)),
        ..amount_columns()
      ]),
    )
    == spell_plan.AbsorptionOnStruckUnit(
      spell4_id: strike,
      proxy_effect_id: 62_204,
      effect_id: 99_060,
    )
    as "the whole plan fails to load, naming the Proxy and the row"
}

pub fn an_absorption_row_aimed_only_at_other_units_is_left_out_and_one_with_the_caster_bit_keeps_its_caster_part_test() -> Nil {
  use <- owned_test.run(60_000)
  let read = fn(flags) {
    list.length(
      modifiers_of(
        row: absorption_row(id: 99_061, target_flags: flags, columns: [
          #("durationTime", Integer(5000)),
          ..amount_columns()
        ]),
      ),
    )
  }
  assert list.map([4, 6], read) == [0, 0]
    as "flags 4 (the area) and 6 (the primary target and the area) aim only at struck units: the type 11 precedent leaves them out"
  assert read(5) == 1 as "flags 5 includes the caster: its caster part is read"
}

pub fn a_periodic_absorption_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // A planted copy of row 46247 (Spell4 27567): tickTime 1000, durationTime 6001.
  assert plan_error(
      row: absorption_row(id: 46_247, target_flags: 1, columns: [
        #("tickTime", Integer(1000)),
        #("durationTime", Integer(6001)),
        #("dataBits01", Integer(1_132_068_864)),
        #("dataBits04", Integer(7)),
      ]),
    )
    == spell_plan.AbsorptionPeriodic(
      spell4_id: strike,
      effect_id: 46_247,
      tick_ms: 1000,
    )
    as "a periodic absorb's reading is not known (the effect type's gap)"
}

pub fn an_absorption_row_with_no_lifetime_fails_the_load_and_one_with_flags_bit_2_lasts_until_removed_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      row: absorption_row(id: 99_062, target_flags: 1, columns: [
        #("dataBits04", Integer(7)),
        ..amount_columns()
      ]),
    )
    == spell_plan.AbsorptionHasNoLifetime(spell4_id: strike, effect_id: 99_062)
    as "no durationTime and no flags bit 2: an absorb with no lifetime is not known"
  let assert [kept] =
    modifiers_of(
      row: absorption_row(id: 99_063, target_flags: 1, columns: [
        #("flags", Integer(2)),
        #("dataBits04", Integer(7)),
        ..amount_columns()
      ]),
    )
  assert kept.row
    == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
    as "the client gives an effect whose flags have bit 2 no end timer"
}

pub fn the_water_shield_row_68969_loads_as_an_absorb_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(absorb) =
    modifier_of(spell4_id: 34_700, effect: client_effect(id: 68_969))
    as "Water Shield - Pell Water: Magic (kind 4) x 5.0 is read for an effect on its caster (0x140566d40 case 4)"
  assert absorb.row
    == LastingRow(delay_ms: 0, duration_ms: 10_000, until_removed: False)
    as "row 68969: delayTime 0, durationTime 10000, flags 0"
}

pub fn an_absorption_row_with_a_formula_kind_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kind 18 is the passed-in value: `damage.caster_unread` refuses it for an effect on its
  // caster (0x140565600).
  let with_kind = fn(kind) {
    plan_error(
      row: absorption_row(id: 99_064, target_flags: 1, columns: [
        #("durationTime", Integer(5000)),
        #("parameterType01", Integer(kind)),
        #("parameterValue01", Float(0.5)),
      ]),
    )
  }
  assert with_kind(18)
    == spell_plan.AbsorptionParameterNotRead(
      spell4_id: strike,
      effect_id: 99_064,
      parameter_kind: 18,
    )
  assert plan_error(
      row: absorption_row(id: 99_065, target_flags: 1, columns: [
        #("durationTime", Integer(5000)),
        #("dataBits01", Integer(2_139_095_040)),
      ]),
    )
    == spell_plan.AbsorptionNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_065,
    )
    as "dataBits01 0x7f800000 is not a finite float"
}

pub fn an_absorption_row_whose_amount_is_0_for_every_caster_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let refused = fn(id, columns) {
    plan_error(
      row: absorption_row(id:, target_flags: 1, columns: [
        #("durationTime", Integer(5000)),
        ..columns
      ]),
    )
    == spell_plan.AbsorptionAmountNotRead(spell4_id: strike, effect_id: id)
  }
  assert modifier_of(spell4_id: 30_724, effect: client_effect(id: 56_356))
    == Error(spell_plan.AbsorptionAmountNotRead(
      spell4_id: 30_724,
      effect_id: 56_356,
    ))
    as "row 56356: dataBits00 0 with a dataBits01 of 100.0 and no parameter is 0 x the base"
  assert refused(99_071, [#("dataBits00", Integer(one_as_float_bits))])
    as "dataBits01 0 with no parameter: 1.0 x 0.0"
  assert refused(99_072, [#("dataBits00", Integer(1_084_227_584))])
    as "a multiplier of 5.0 with a base of 0.0 and no parameter, as 140 rows hold"
  assert refused(99_073, [
    #("parameterType00", Integer(13)),
    #("parameterValue00", Float(0.0)),
  ])
    as "a stat parameter whose value is 0 gives nothing"
  // Each of these gives the caster something: a stat parameter, a flat parameter with a
  // multiplier, or a multiplier and a base.
  let read = fn(id, columns) {
    list.length(
      modifiers_of(
        row: absorption_row(id:, target_flags: 1, columns: [
          #("durationTime", Integer(5000)),
          ..columns
        ]),
      ),
    )
    == 1
  }
  assert read(99_074, [
    #("parameterType00", Integer(13)),
    #("parameterValue00", Float(4.0)),
  ])
    as "row 97347: dataBits00 0, dataBits01 0 and Support Power x 4.0 is read"
  assert read(99_075, [
    #("dataBits00", Integer(one_as_float_bits)),
    #("parameterType00", Integer(10)),
    #("parameterValue00", Float(2.0)),
  ])
    as "a flat parameter (the level) with a multiplier gives a base"
  assert read(99_076, amount_columns())
}

// ---- the kinds and the measure ----

pub fn effect_kind_reads_absorption_aimed_at_the_caster_and_the_measure_counts_the_plans_refusals_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 29) == effect_kind.Absorption
  assert effect_kind.is_read(effect_type: 29)
    as "the measure counts type 29 handled"
  let aimed = fn(flags) {
    effect_kind.is_row_read(effect_type: 29, target_flags: flags)
  }
  assert list.map([1, 2, 4, 5, 6], aimed) == [True, True, False, True, False]
    as "read for the caster (bit 1) or the primary target alone (2); 4 and 6 aim only at struck units"
  // Each refusal of the plan is counted as not read, in a spell no Proxy starts on each
  // struck unit.
  use counted <- spell_tables.with_measure
  let none = spell_tables.pressed
  assert counted(spectral_form_row(), none) as "row 178144 is read"
  assert !counted(Spell4Effects(..spectral_form_row(), tick_time: 1000), none)
    as "a periodic row is refused by the plan, so it is not read"
  assert !counted(Spell4Effects(..spectral_form_row(), duration_time: 0), none)
    as "a row with no lifetime is refused"
  assert counted(
    Spell4Effects(..spectral_form_row(), duration_time: 0, flags: 2),
    none,
  )
    as "and one with flags bit 2 is read"
  assert !counted(
    Spell4Effects(..spectral_form_row(), parameter_type01: 18),
    none,
  )
    as "a formula kind not read (18, the passed-in value) is refused"
  assert !counted(
    Spell4Effects(..spectral_form_row(), data_bits01: 2_139_095_040),
    none,
  )
    as "a non-finite dataBits01 is refused"
  assert !counted(
    Spell4Effects(..spectral_form_row(), prerequisite_id_target_apply: 99),
    none,
  )
    as "a row behind a target apply prerequisite is held by the plan and applied by no go, so it is not read"
  assert !counted(
    Spell4Effects(
      ..spectral_form_row(),
      parameter_type00: 0,
      parameter_type01: 0,
      parameter_value00: 0.0,
      parameter_value01: 0.0,
    ),
    none,
  )
    as "a row whose amount is 0 for every caster is refused, so it is not read"
  assert !counted(Spell4Effects(..spectral_form_row(), target_flags: 4), none)
    as "a row aimed at the area alone is not read"
  let on_primary = Spell4Effects(..spectral_form_row(), target_flags: 2)
  assert counted(on_primary, none)
    as "aimed at the primary target in a spell cast on the caster, it is read"
  assert !counted(
    on_primary,
    spell_tables.started_on_each_struck(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
    ),
  )
    as "in a spell a Proxy starts on each struck unit it fails the load, so it is not read"
}

// ---- the client's tables ----

pub fn spectral_form_holds_its_absorption_and_the_plans_load_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(innate) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(38_012))
    as "the plans hold the Esper's innate (`table_rows -- Spell4Effects spellId=58586`)"
  let assert Ok(spectral_form) =
    list.find(
      spell_plan.tree(spell: innate, started: fn(_) { True }),
      fn(spell) { spell.spell4_id.value == 58_586 },
    )
    as "the innate's tree holds Spell4 58586"
  let assert [absorb] =
    list.filter(spectral_form.modifiers, fn(row) {
      row.effect_id == Spell4EffectsId(178_144)
    })
    as "row 178144 is one of its modifiers"
  assert absorb.change
    == spell_plan.AbsorbChange(Absorption(
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 12, value: 2.5309998989105225),
        Parameter(kind: 13, value: 2.5309998989105225),
        Parameter(kind: 0, value: 0.0),
        Parameter(kind: 0, value: 0.0),
      ]),
      mask: 7,
      aim: AimsAtCaster,
    ))
  assert absorb.row
    == LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False)
    as "5000 ms"
}
