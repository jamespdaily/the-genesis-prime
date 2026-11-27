//// The heals and shield overloads of the plan (`genesis_prime/shared/spell_plan`
//// `Heal`, `TickingHeal`, `Lasting`, `genesis_prime/shared/effect_kind`).
//// Expected values come from these places.
//// - `Spell4Effects.effectType.118`: a HealShields row restores shield to the unit it
////   lands on, by the amount of `0x140565600`'s formula; its columns are the Medic's
////   Energize 228914 (targetFlags 1, delayTime 10, dataBits00 1.0, dataBits01 0,
////   parameterType00 22 with value 0.3, phaseFlags -1, no tickTime), the Warrior's
////   Onslaught row 210834 (tickTime 1000, durationTime 8000, flags 16, dataBits04 1,
////   parameterType00 16 with value 0.125) and the Medic's Hypercharge row 146893
////   (targetFlags 4) (`table_rows -- Spell4Effects spellId=69450`, `=46867`, `=60718`).
//// - `Spell4Effects.effectType.10`: a Heal row restores health by the same formula; the
////   rows below are read with `table_rows -- Spell4Effects 62019 94498 89598 80077
////   69917`: 62019 (spell 32820, targetFlags 2, parameter 13 x 0.3281 and 10 x 17.51,
////   dataBits00 1.0, no delay), 94498 (spell 41926, targetFlags 5, damageType 1, 13 x
////   0.5368 and 10 x 23.36), 89598 (spell 38507, targetFlags 4), 80077 (spell 32821,
////   targetFlags 2, tickTime 1000) and 69917 (spell 34985, parameter 18 x 200).
//// - `0x140566ad0` and `0x140566d40`: the parameter types the formula reads; the
////   passed-in value (18) and the caster's Weapon and Weapon DPS (6 and 9,
////   `Spell4Effects.parameterType.6_9`) the server does not read for an effect on its
////   caster. Row 94299 (Esper - Tech - Rank 3 -
////   Shield Heal Proc, Spell4 41868): targetFlags 2, dataBits00 1.0, parameterType00 3
////   (Technology, `0x140566d40` case 3) with value 1.5, no tickTime
////   (`table_rows -- Spell4Effects 94299`).
//// - `Spell4Effects.targetFlags`: bit 1 the caster, 2 the primary target, 4 the area. The
////   target of every cast is the caster (`cast`'s doc), so a flags-2 row of a spell cast
////   on the caster heals the caster; a child started on each struck unit has that unit
////   as its primary target, which the plan refuses for a heal.
//// - `Spell4Effects.effectType.64`: a ShieldOverload row marks the units it lands on for
////   its durationTime; the Medic's Meltdown row 147229 is aimed at the area (targetFlags
////   4) for 4000 ms, and the plan lists it on each struck unit as a Fluff row is
////   (`table_rows -- Spell4Effects spellId=60796`).
//// - The type 11 precedent (`effect_kind.is_row_read`): a row aimed only at other units
////   is left out of the plan and counted as not read.
//// The rows are in memory: the whole plan is read from the client's tables in the last
//// test.

import cast_support
import client_tables
import fixture_tables
import genesis_prime/game/effect_row_read
import genesis_prime/shared/damage.{Formula, Parameter}
import genesis_prime/shared/effect_kind
import genesis_prime/shared/lasting.{LastingRow}
import genesis_prime/shared/lasts
import genesis_prime/shared/spell_plan.{
  AimedAtOtherUnits, AimsAtArea, AimsAtCaster, AimsAtCasterAndArea,
  AimsAtCasterAndPrimaryTarget, AimsAtPrimaryTarget, Always, Applied, Heal,
  Lasting, LeftOut, TickingHeal,
}
import genesis_prime/shared/spend
import genesis_prime/shared/target_mechanic
import genesis_prime/shared/ticking
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import genesis_prime/table/spell_level
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import owned_test
import planted_table.{Integer}
import spell_tables
import unitest

/// 1.0 as 32 float bits.
const one_as_float_bits = 1_065_353_216

/// Energize's row 228914 as the client holds it.
fn energize_row() -> Spell4Effects {
  Spell4Effects(
    ..spell_tables.blank_effect(
      id: 228_914,
      spell: 69_450,
      effect_type: 118,
      target_flags: 1,
    ),
    delay_time: 10,
    data_bits00: one_as_float_bits,
    parameter_type00: 22,
    parameter_value00: 0.3,
  )
}

/// A heal row of Energize's with these columns changed.
fn heal_aimed_at(flags flags: Int) -> Spell4Effects {
  Spell4Effects(..energize_row(), target_flags: flags)
}

/// The Warrior's row 210834: 0.125 of the maximum shield each 1000 ms for 8000 ms.
fn onslaught_row() -> Spell4Effects {
  Spell4Effects(
    ..spell_tables.blank_effect(
      id: 210_834,
      spell: 46_867,
      effect_type: 118,
      target_flags: 1,
    ),
    tick_time: 1000,
    duration_time: 8000,
    flags: 16,
    data_bits00: one_as_float_bits,
    data_bits04: 1,
    parameter_type00: 16,
    parameter_value00: 0.125,
  )
}

/// The heals the plan lists for these rows read in a spell nothing starts on each struck
/// unit (`spell_plan.read_row`: `Applied` and `Held` rows are in the spell's list).
fn heals_of(effects effects: List(Spell4Effects)) -> List(spell_plan.Heal) {
  spell_tables.read_rows(effects:, place: spell_tables.pressed)
  |> list.flat_map(fn(reading) {
    case reading {
      Ok(reading) ->
        list.filter_map(
          spell_tables.planned_kinds(reading:),
          spell_plan.as_heal,
        )
      Error(error) ->
        panic as { "the row is refused: " <> spell_plan.describe(error:) }
    }
  })
}

/// The heal the plan reads from one row in a spell nothing starts on each struck unit, or the
/// error that fails the load (`spell_plan.read_row`).
fn heal_read(
  effect effect: Spell4Effects,
) -> Result(spell_plan.Heal, spell_plan.PlanError) {
  use reading <- result.map(spell_tables.read_row(
    effect:,
    place: spell_tables.pressed,
  ))
  let assert [heal] =
    list.filter_map(spell_tables.planned_kinds(reading:), spell_plan.as_heal)
    as "the row is read as one heal"
  heal
}

fn heal_ids(heals heals: List(spell_plan.Heal)) -> List(Int) {
  list.map(heals, fn(heal) { heal.effect_id.value })
}

// ---- the rows of the plan ----

pub fn a_heal_shields_row_aimed_at_the_caster_is_a_shield_heal_with_its_formula_delay_and_phases_test() -> Nil {
  use <- owned_test.run(5000)
  assert heal_read(effect: energize_row())
    == Ok(Heal(
      effect_id: Spell4EffectsId(228_914),
      vital: effect_kind.Shield,
      phase_flags: -1,
      aim: AimsAtCaster,
      condition: Always,
      tag: spend.EqualTo(value: 0),
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 22, value: 0.3),
        Parameter(kind: 0, value: 0.0),
        Parameter(kind: 0, value: 0.0),
        Parameter(kind: 0, value: 0.0),
      ]),
      delay_ms: 10,
    ))
    as "row 228914: kind 22 x 0.3, dataBits00 1.0 (0x3F800000), dataBits01 0, delay 10, every phase"
}

pub fn a_heal_shields_row_aimed_at_the_primary_target_is_read_in_a_spell_cast_on_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(heal) = heal_read(effect: heal_aimed_at(flags: 2))
  assert heal.aim == AimsAtPrimaryTarget
    as "targetFlags 2 is the primary target, which the target of a cast on the caster is"
  assert spell_tables.read_row(
      effect: heal_aimed_at(flags: 2),
      place: spell_tables.pressed,
    )
    == Ok(
      Applied(
        spell_plan.ReadEffects(effects: [
          spell_plan.effect_of(kind: spell_plan.HealEffect(heal)),
        ]),
      ),
    )
    as "a child a Proxy aimed at the caster starts is cast on the caster: spell_plan.target_of starts flags 1 and 2 there"
}

pub fn a_heal_shields_row_aimed_at_the_primary_target_of_a_child_on_each_struck_unit_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let on_each_struck =
    spell_tables.started_on_each_struck(
      spell4_id: 69_450,
      proxy_effect_id: 228_915,
    )
  assert spell_tables.read_row(
      effect: Spell4Effects(
        ..heal_aimed_at(flags: 2),
        id: 146_893,
        spell_id: 60_718,
      ),
      place: on_each_struck,
    )
    == Error(spell_plan.HealOnStruckUnit(
      spell4_id: 69_450,
      proxy_effect_id: 228_915,
      effect_id: 146_893,
    ))
    as "the child's primary target is a struck unit, and a shield heal on one is not built"
  assert spell_tables.read_row(
      effect: Spell4Effects(..heal_aimed_at(flags: 1), spell_id: 60_718),
      place: on_each_struck,
    )
    |> result.is_ok
    as "a row that includes the caster heals the caster, whichever unit the child is cast on"
}

pub fn a_heal_shields_row_aimed_only_at_other_units_is_left_out_and_one_with_the_caster_bit_keeps_its_aim_test() -> Nil {
  use <- owned_test.run(5000)
  let rows =
    list.map([4, 5, 6, 7], fn(flags) {
      Spell4Effects(
        ..heal_aimed_at(flags:),
        id: 146_890 + flags,
        spell_id: 60_718,
      )
    })
  let heals = heals_of(effects: rows)
  assert heal_ids(heals:) == [146_895, 146_897]
    as "targetFlags 4 (row 146893's) and 6 aim only at other units; 5 and 7 include the caster"
  assert list.map(heals, fn(heal) { heal.aim })
    == [AimsAtCaster, AimsAtCasterAndPrimaryTarget]
    as "5 (the caster and the area) keeps the caster alone, the area being a friendly spell's (#834); 7 keeps the caster and the primary target, whose heal lands nothing until #570"
}

pub fn a_periodic_heal_shields_row_is_held_as_ticking_and_not_applied_test() -> Nil {
  use <- owned_test.run(5000)
  assert heals_of(effects: [onslaught_row()])
    == [
      TickingHeal(
        effect_id: Spell4EffectsId(210_834),
        vital: effect_kind.Shield,
        phase_flags: -1,
        aim: AimsAtCaster,
        condition: Always,
        tag: spend.EqualTo(value: 0),
        formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
          Parameter(kind: 16, value: 0.125),
          Parameter(kind: 0, value: 0.0),
          Parameter(kind: 0, value: 0.0),
          Parameter(kind: 0, value: 0.0),
        ]),
        schedule: ticking.Schedule(
          delay_ms: 0,
          tick_ms: 1000,
          duration_ms: 8000,
          count: ticking.Ticks(8),
        ),
      ),
    ]
    as "row 210834: tickTime 1000 and durationTime 8000; the cast rule does not apply it, as a TickingGain"
}

pub fn the_esper_shield_heal_proc_row_94299_loads_as_a_shield_heal_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(row) =
    spell4_effects.get(
      tables: fixture_tables.shared(),
      id: Spell4EffectsId(94_299),
    )
    as "the fixture holds the row"
  let assert Ok(Heal(vital: effect_kind.Shield, ..)) = heal_read(effect: row)
    as "Esper - Tech - Rank 3 - Shield Heal Proc: Technology (kind 3) x 1.5 is read for an effect on its caster"
  Nil
}

pub fn a_heal_shields_row_with_a_parameter_the_caster_formula_does_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([6, 9], fn(kind) {
    let row =
      Spell4Effects(..energize_row(), id: 99_118, parameter_type00: kind)
    assert heal_read(effect: row)
      == Error(spell_plan.ParameterNotRead(
        spell4_id: 69_450,
        effect_id: 99_118,
        row: spell_plan.HealRow,
        parameter_kind: kind,
      ))
      as {
        "type "
        <> int.to_string(kind)
        <> " is the caster's Weapon or Weapon DPS (0x140b0b580), which an effect on its caster does not read"
      }
  })
  list.each(
    [
      1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23,
      25, 26,
    ],
    fn(kind) {
      let row =
        Spell4Effects(..energize_row(), id: 99_119, parameter_type00: kind)
      let assert Ok(Heal(..)) = heal_read(effect: row)
        as {
          "0x140566ad0, 0x140566d40 or the passed-in value (0x140565600) reads type "
          <> int.to_string(kind)
        }
    },
  )
  let not_a_number =
    Spell4Effects(..energize_row(), id: 99_120, data_bits00: 0x7F800000)
  assert heal_read(effect: not_a_number)
    == Error(spell_plan.HealNumberNotFinite(
      spell4_id: 69_450,
      effect_id: 99_120,
    ))
    as "dataBits00 is a 32-bit float: 0x7F800000 is infinity"
}

pub fn a_shield_overload_row_aimed_at_the_area_is_a_lasting_row_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let meltdown =
    Spell4Effects(
      ..spell_tables.blank_effect(
        id: 147_229,
        spell: 60_796,
        effect_type: 64,
        target_flags: 4,
      ),
      duration_time: 4000,
    )
  assert spell_tables.read_rows(
      effects: [
        meltdown,
        Spell4Effects(..meltdown, id: 1, target_flags: 1),
        Spell4Effects(..meltdown, id: 2, target_flags: 2),
      ],
      place: spell_tables.pressed,
    )
    == [
      Ok(
        Applied(
          spell_plan.ReadEffects(effects: [
            spell_plan.effect_of(
              kind: spell_plan.LastingEffect(Lasting(
                effect_id: Spell4EffectsId(147_229),
                phase_flags: -1,
                aim: AimsAtArea,
                row: LastingRow(
                  delay_ms: 0,
                  lasts: lasts.For(duration_ms: 4000),
                ),
                condition: Always,
                tag: spend.EqualTo(value: 0),
              )),
            ),
          ]),
        ),
      ),
      Ok(LeftOut(why: AimedAtOtherUnits)),
      Ok(LeftOut(why: AimedAtOtherUnits)),
    ]
    as "row 147229: aimed at the area, 4000 ms, no delay; 35 rows aim at the caster or the primary target, whose shield hold at 0 is not built"
}

pub fn a_heal_in_a_struck_unit_child_is_refused_by_place_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 205411 of Spell4 78280 is aimed at the primary target (flags 2); Proxy 137988 of
  // Spell4 57685 starts 78280 on each unit its area strikes (flags 4), and the plan fails
  // the load on the shape, so the measure counts the row as not read.
  let proxy =
    Spell4Effects(
      ..spell_tables.blank_effect(
        id: 137_988,
        spell: 57_685,
        effect_type: 26,
        target_flags: 4,
      ),
      data_bits00: 78_280,
    )
  let heal =
    Spell4Effects(..heal_aimed_at(flags: 2), id: 205_411, spell_id: 78_280)
  let struck =
    spell_plan.struck_unit_children(tables: fixture_tables.shared(), effects: [
      proxy,
      heal,
    ])
  assert dict.to_list(struck)
    == [
      #(
        78_280,
        spell_plan.StruckBy(spell4_id: 57_685, proxy_effect_id: 137_988),
      ),
    ]
    as "only the Proxy's child is made on each struck unit, by the Proxy that starts it"
  let place =
    spell_tables.started_on_each_struck(
      spell4_id: 57_685,
      proxy_effect_id: 137_988,
    )
  assert spell_tables.read_row(effect: heal, place:)
    == Error(spell_plan.HealOnStruckUnit(
      spell4_id: 57_685,
      proxy_effect_id: 137_988,
      effect_id: 205_411,
    ))
    as "the row's spell is made on each struck unit, whose shield a heal on the primary target is not built for"
  assert !spell_tables.measure_reads(effect: heal, place:)
  assert result.is_ok(spell_tables.read_row(
    effect: heal,
    place: spell_tables.pressed,
  ))
    as "the same row under a Proxy aimed at the caster is read: no spell is made on each struck unit"
  let assert Ok(Applied(_) as reading) =
    spell_tables.read_row(
      effect: Spell4Effects(..heal, target_flags: 1),
      place:,
    )
    as "a row that includes the caster heals the caster in a struck child too"
  let assert [spell_plan.HealEffect(on_the_caster)] =
    spell_tables.planned_kinds(reading:)
  assert on_the_caster.aim == AimsAtCaster
}

// ---- the kinds ----

pub fn effect_kind_reads_heal_shields_for_the_caster_and_shield_overload_for_the_area_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 118)
    == effect_kind.Heal(effect_kind.Shield)
  assert effect_kind.kind_of(effect_type: 64) == effect_kind.ShieldOverload
  assert effect_kind.is_read(effect_type: 118)
    && effect_kind.is_read(effect_type: 64)
    as "the measure counts both types handled"
  let read = fn(effect_type, flags) {
    effect_kind.is_row_read(effect_type:, target_flags: flags)
  }
  assert list.map([1, 2, 4, 5, 6, 7], read(118, _))
    == [True, True, False, True, False, True]
    as "a heal is read for the caster (bit 1) or the primary target alone (2): 4 and 6 aim at other units"
  assert list.map([1, 2, 4, 5, 6, 7], read(64, _))
    == [False, False, True, False, False, False]
    as "an overload is read for the area alone (4)"
}

pub fn heal_kind_covers_types_10_and_118_with_their_vital_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 10)
    == effect_kind.Heal(vital: effect_kind.Health)
    as "Spell4Effects.effectType.10 is Heal: it restores health"
  assert effect_kind.kind_of(effect_type: 118)
    == effect_kind.Heal(vital: effect_kind.Shield)
    as "Spell4Effects.effectType.118 is HealShields: it restores shield"
  assert effect_kind.is_read(effect_type: 10)
    as "the measure counts type 10 handled"
  let read = fn(flags) {
    effect_kind.is_row_read(effect_type: 10, target_flags: flags)
  }
  assert list.map([1, 2, 5, 4, 6], read) == [True, True, True, False, False]
    as "a heal is read for the caster (bit 1) or the primary target alone (2): 4 and 6 aim at other units"
}

/// Row 62019 of Spell4 32820 as the client holds it (`table_rows -- Spell4Effects 62019`).
fn mind_over_body_row() -> Spell4Effects {
  Spell4Effects(
    ..spell_tables.blank_effect(
      id: 62_019,
      spell: 32_820,
      effect_type: 10,
      target_flags: 2,
    ),
    data_bits00: one_as_float_bits,
    parameter_type00: 13,
    parameter_type01: 10,
    parameter_value00: 0.3280999958515167,
    parameter_value01: 17.510000228881836,
  )
}

pub fn mind_over_body_row_reads_as_a_health_heal_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_tables.read_row(
      effect: mind_over_body_row(),
      place: spell_tables.pressed,
    )
    == Ok(
      Applied(
        spell_plan.ReadEffects(effects: [
          spell_plan.effect_of(
            kind: spell_plan.HealEffect(Heal(
              effect_id: Spell4EffectsId(62_019),
              vital: effect_kind.Health,
              phase_flags: -1,
              aim: AimsAtPrimaryTarget,
              condition: Always,
              tag: spend.EqualTo(value: 0),
              formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
                Parameter(kind: 13, value: 0.3280999958515167),
                Parameter(kind: 10, value: 17.510000228881836),
                Parameter(kind: 0, value: 0.0),
                Parameter(kind: 0, value: 0.0),
              ]),
              delay_ms: 0,
            )),
          ),
        ]),
      ),
    )
    as "row 62019: targetFlags 2 aims at the primary target, 13 x 0.3281 and 10 x 17.51, dataBits00 1.0, no delay"
}

pub fn medic_flash_row_reads_as_a_health_heal_on_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Spell4Effects(
      ..spell_tables.blank_effect(
        id: 94_498,
        spell: 41_926,
        effect_type: 10,
        target_flags: 5,
      ),
      damage_type: 1,
      data_bits00: one_as_float_bits,
      parameter_type00: 13,
      parameter_type01: 10,
      parameter_value00: 0.5368000268936157,
      parameter_value01: 23.360000610351562,
    )
  let assert Ok(Applied(_) as reading) =
    spell_tables.read_row(effect: row, place: spell_tables.pressed)
    as "row 94498 is read"
  let assert [spell_plan.HealEffect(heal)] =
    spell_tables.planned_kinds(reading:)
  assert heal.vital == effect_kind.Health
  assert heal.aim == AimsAtCaster
    as "targetFlags 5 includes the caster (bit 1) and the area (4): the caster part is read"
  assert heal.effect_id == Spell4EffectsId(94_498)
}

pub fn a_heal_row_aimed_at_other_units_is_left_out_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Spell4Effects(
      ..mind_over_body_row(),
      id: 89_598,
      spell_id: 38_507,
      target_flags: 4,
    )
  assert spell_tables.read_row(effect: row, place: spell_tables.pressed)
    == Ok(LeftOut(why: AimedAtOtherUnits))
    as "row 89598: targetFlags 4 is the area alone, the units a strike hits"
}

pub fn a_heal_row_that_lives_shorter_than_a_tick_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Spell4Effects(
      ..mind_over_body_row(),
      id: 80_077,
      spell_id: 32_821,
      tick_time: 1000,
      flags: 512,
    )
  assert spell_tables.read_row(effect: row, place: spell_tables.pressed)
    == Error(spell_plan.HealNoTick(
      spell4_id: 32_821,
      effect_id: 80_077,
      tick_ms: 1000,
      duration_ms: 0,
    ))
    as "row 80077 as edited: tickTime 1000, durationTime 0 and no flags bit 2, so no tick lands within its life (genesis_prime/shared/ticking `NoTick`)"
}

pub fn a_heal_row_with_an_unread_parameter_or_number_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let passed_in =
    Spell4Effects(
      ..mind_over_body_row(),
      id: 69_917,
      spell_id: 34_985,
      target_flags: 1,
      flags: 524_304,
      parameter_type00: 18,
      parameter_type01: 0,
      parameter_value00: 200.0,
      parameter_value01: 0.0,
    )
  let assert Ok(Heal(formula:, ..)) = heal_read(effect: passed_in)
    as "row 69917: parameter 18 is the value passed in, which an effect on its caster reads (0x140565600)"
  assert formula.parameters
    == [
      Parameter(kind: 18, value: 200.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]
    as "and keeps it as the row gives it"
  let weapon_dps = Spell4Effects(..passed_in, parameter_type00: 9)
  assert heal_read(effect: weapon_dps)
    == Error(spell_plan.ParameterNotRead(
      spell4_id: 34_985,
      effect_id: 69_917,
      row: spell_plan.HealRow,
      parameter_kind: 9,
    ))
    as "parameter 9, the caster's Weapon DPS, is not read"
  let not_a_number =
    Spell4Effects(..mind_over_body_row(), data_bits00: 0x7F800000)
  assert heal_read(effect: not_a_number)
    == Error(spell_plan.HealNumberNotFinite(
      spell4_id: 32_820,
      effect_id: 62_019,
    ))
    as "dataBits00 is a 32-bit float: 0x7F800000 is infinity"
}

pub fn a_heal_row_on_each_struck_unit_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let on_each_struck =
    spell_tables.started_on_each_struck(
      spell4_id: 57_685,
      proxy_effect_id: 137_988,
    )
  assert spell_tables.read_row(
      effect: mind_over_body_row(),
      place: on_each_struck,
    )
    == Error(spell_plan.HealOnStruckUnit(
      spell4_id: 57_685,
      proxy_effect_id: 137_988,
      effect_id: 62_019,
    ))
    as "a Heal row aimed at the primary target in a child a Proxy casts on each struck unit would heal a struck unit, which no rule builds"
  assert spell_tables.read_row(
      effect: Spell4Effects(..mind_over_body_row(), target_flags: 1),
      place: on_each_struck,
    )
    |> result.is_ok
    as "a row that names the caster alone heals the caster, whichever unit the child is cast on"
  assert list.map([3, 7], fn(flags) {
      spell_tables.read_row(
        effect: Spell4Effects(..mind_over_body_row(), target_flags: flags),
        place: on_each_struck,
      )
    })
    == list.repeat(
      Error(spell_plan.HealOnStruckUnit(
        spell4_id: 57_685,
        proxy_effect_id: 137_988,
        effect_id: 62_019,
      )),
      2,
    )
    as "a row that names the caster and the primary target also names the struck unit, so the load fails as it does for flags 2"
}

/// Which of a heal row's planned shapes is told to another player, by the row's delay,
/// period and aim (`spell_plan.telling_of`): the rows are Mind Over Body's 62019 with the
/// columns that differ (Bolster's 80077 is the periodic shape: tickTime 1000, durationTime
/// 8000, targetFlags 2). Row 62019's delay of 20 ms is edited in: no client row is both.
pub fn a_heal_row_is_told_at_the_go_at_each_tick_or_not_at_all_by_its_delay_period_and_aim_test() -> Nil {
  use <- owned_test.run(5000)
  let periodic = fn(row: Spell4Effects) {
    Spell4Effects(..row, tick_time: 1000, duration_time: 8000)
  }
  let cases = [
    #(
      mind_over_body_row(),
      spell_plan.ToldAtGo,
      "an instant row aimed at the primary target is told at the go (62019 as the client holds it)",
    ),
    #(
      Spell4Effects(..mind_over_body_row(), target_flags: 3),
      spell_plan.ToldAtGo,
      "an instant row aimed at the caster and the primary target is told at the go",
    ),
    #(
      Spell4Effects(..mind_over_body_row(), target_flags: 1),
      spell_plan.NotTold,
      "an instant row aimed at the caster alone is the caster's own",
    ),
    #(
      Spell4Effects(..mind_over_body_row(), delay_time: 20),
      spell_plan.NotTold,
      "an instant row with a delay lands after the go, which the go's tell does not carry",
    ),
    #(
      periodic(mind_over_body_row()),
      spell_plan.ToldAtEachTick,
      "a periodic row aimed at the primary target is told at each tick (Bolster's 80077 shape)",
    ),
    #(
      periodic(Spell4Effects(..mind_over_body_row(), target_flags: 3)),
      spell_plan.ToldAtEachTick,
      "a periodic row aimed at the caster and the primary target is told at each tick",
    ),
    #(
      periodic(Spell4Effects(..mind_over_body_row(), target_flags: 1)),
      spell_plan.NotTold,
      "a periodic row aimed at the caster alone is the caster's own tick",
    ),
  ]
  list.each(cases, fn(one) {
    let #(row, telling, reason) = one
    let assert [heal] = heals_of(effects: [row])
    assert spell_plan.telling_of(heal:) == telling as reason
  })
}

// ---- the client's tables ----

pub fn the_plans_hold_energizes_shield_heal_the_warriors_ticking_row_and_meltdowns_overload_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert [Heal(effect_id: Spell4EffectsId(228_914), delay_ms: 10, ..)] =
    spell_plan.payloads(
      spell: cast_support.planned_spell(base: 46_615, spell4_id: 69_450),
      as_kind: spell_plan.as_heal,
    )
    as "Spell4Effects spellId=69450: 228914 is the Medic's only shield heal on the caster"
  let assert [
    TickingHeal(
      effect_id: Spell4EffectsId(210_834),
      schedule: ticking.Schedule(tick_ms: 1000, count: ticking.Ticks(8), ..),
      ..,
    ),
  ] =
    spell_plan.payloads(
      spell: cast_support.planned_spell(base: 30_828, spell4_id: 46_867),
      as_kind: spell_plan.as_heal,
    )
    as "Spell4Effects spellId=46867: 210834, held and not applied"
  assert spell_plan.payloads(
      spell: cast_support.planned_spell(base: 46_615, spell4_id: 60_718),
      as_kind: spell_plan.as_heal,
    )
    == []
    as "Spell4Effects spellId=60718: 146893 has targetFlags 4, aimed at other units, so it is left out"
  let assert [Lasting(effect_id: Spell4EffectsId(147_229), aim: AimsAtArea, ..)] =
    list.filter(
      spell_plan.payloads(
        spell: cast_support.planned_spell(base: 46_615, spell4_id: 60_796),
        as_kind: spell_plan.as_lasting,
      ),
      fn(row) { row.effect_id.value == 147_229 },
    )
    as "Spell4Effects spellId=60796: 147229, a ShieldOverload aimed at the area, is a lasting row"
  Nil
}

/// Whether the Prerequisite `id` holds a type 37 (chance) condition, in its own conditions
/// or in a row nested through a type 11 condition (`Prerequisite.prerequisiteTypeId.11`
/// names the nested row in its objectId); `seen` stops a row that nests itself.
fn holds_a_chance(
  rows rows: dict.Dict(Int, prerequisite.Prerequisite),
  id id: Int,
  seen seen: set.Set(Int),
) -> Bool {
  case set.contains(seen, id), dict.get(rows, id) {
    True, _ | _, Error(Nil) -> False
    False, Ok(row) ->
      list.any(
        [
          #(row.prerequisite_type_id0, row.object_id0),
          #(row.prerequisite_type_id1, row.object_id1),
          #(row.prerequisite_type_id2, row.object_id2),
        ],
        fn(condition) {
          case condition.0 {
            37 -> True
            11 ->
              holds_a_chance(rows:, id: condition.1, seen: set.insert(seen, id))
            _ -> False
          }
        },
      )
  }
}

pub fn every_periodic_heal_row_of_an_ability_pressed_at_a_player_is_read_as_a_ticking_heal_at_the_primary_target_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  // An ability is the Spell4Base of a SpellLevel row's spell, and it is pressed at a
  // player when its Spell4TargetMechanics row is a kind the client's picker sends a
  // target for (`0x14055bdc0`) and is beneficial (flags bit 0).
  let pressed_at_a_player =
    spell_level.all(tables)
    |> list.filter_map(fn(level) {
      spell4.get(tables:, id: id.Spell4Id(level.spell4_id))
    })
    |> list.map(fn(spell) { spell.spell4_base_id_base_spell })
    |> list.unique
    |> list.filter(fn(base) {
      let assert Ok(targeting) =
        target_mechanic.targeting_of(tables:, base_id: Spell4BaseId(base))
        as "every ability's base has its target rows"
      targeting.kind == target_mechanic.Targeted
      && target_mechanic.is_beneficial(flags: targeting.mechanics_flags)
    })
  let tier_spells =
    list.filter(spell4.all(tables), fn(spell) {
      list.contains(pressed_at_a_player, spell.spell4_base_id_base_spell)
    })
    |> list.map(fn(spell) { spell.id })
    |> set.from_list
  let periodic_heals =
    list.filter(spell4_effects.all(tables), fn(row) {
      set.contains(tier_spells, row.spell_id)
      && list.contains([10, 118], row.effect_type)
      && row.tick_time > 0
      && effect_kind.is_row_read(
        effect_type: row.effect_type,
        target_flags: row.target_flags,
      )
    })
  assert periodic_heals != []
    as "Bolster's rows (Spell4Effects 80077) are periodic heals of an ability pressed at a player, so the table is not empty"
  let sources = spell_plan.sources_of(tables:)
  list.each(periodic_heals, fn(row) {
    let name = "row " <> int.to_string(row.id) <> ": "
    assert row.prerequisite_id_caster_apply == 0
      && row.prerequisite_id_target_apply == 0
      as { name <> "no prerequisite, so no gate is read at a tick" }
    let assert Ok(reading) =
      spell_plan.read_row(
        tables:,
        sources:,
        place: spell_tables.pressed,
        effect: row,
      )
      as { name <> "the plan reads the row" }
    let assert [heal] =
      list.filter_map(spell_tables.planned_kinds(reading:), spell_plan.as_heal)
      as { name <> "the plan holds the row once" }
    let assert TickingHeal(aim:, ..) = heal
      as { name <> "a row with a tickTime is a ticking heal" }
    assert spell_plan.reaches_primary_target(aim:)
      as { name <> "the heal reaches the primary target" }
    assert spell_plan.telling_of(heal:) == spell_plan.ToldAtEachTick
      as { name <> "the ally is told at each tick" }
  })
}

pub fn no_heal_row_of_the_clients_tables_holds_a_type_37_prerequisite_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows =
    prerequisite.all(tables)
    |> list.map(fn(row) { #(row.id, row) })
    |> dict.from_list
  let heals =
    list.filter(spell4_effects.all(tables), fn(row) {
      list.contains([10, 118], row.effect_type)
    })
  assert heals != [] as "the client's tables hold heal rows"
  assert list.filter(heals, fn(row) {
      holds_a_chance(
        rows:,
        id: row.prerequisite_id_caster_apply,
        seen: set.new(),
      )
      || holds_a_chance(
        rows:,
        id: row.prerequisite_id_target_apply,
        seen: set.new(),
      )
    })
    |> list.map(fn(row) { row.id })
    == []
    as "a heal row with a chance gate would take a roll again at the go after the strike took one"
}

// ---- the area of a friendly spell ----

/// Whether the area finds allies for a spell of a target mechanic of these `flags` (the
/// Spell4TargetMechanics row's `flags`: bit 0 beneficial) whose own rows are `effects`, with an
/// area row of `target_selection` (0 for none).
fn finds_allies(
  flags flags: Int,
  effects effects: List(Spell4Effects),
  target_selection target_selection: Int,
) -> Bool {
  spell_plan.area_finds_allies(
    mechanics_flags: flags,
    effects:,
    target_selection:,
  )
}

/// A spell's area finds the caster's allies when its mechanic is beneficial (flags bit 0,
/// `FillSpellRecord` 0x140568540 puts it in the record's bit 26), none of its damage or
/// crowd-control rows aims past the caster, and its area row orders by distance, at random or
/// by missing health (targetSelection 1, 2, 3 and 5, which the strike builds). Rows: the
/// mechanics Crisis Wave (row 7, flags 9) and Triage (row 28, flags 41) hold, a hostile one
/// (Impale's and Crush's flags 16: 27 planned abilities hit foes through a Proxy child with no
/// damage row in their own spell), a spell with a damage row aimed at the area, and the order by
/// lowest health (4), which no planned ability names.
pub fn a_spells_area_finds_allies_when_its_mechanic_is_beneficial_it_hits_no_foes_and_its_order_is_built_test() -> Nil {
  use <- owned_test.run(5000)
  let damage_at_the_area =
    spell_tables.blank_effect(id: 1, spell: 1, effect_type: 8, target_flags: 4)
  let state_at_the_primary_target =
    spell_tables.blank_effect(id: 2, spell: 1, effect_type: 4, target_flags: 2)
  let heal_at_the_area =
    spell_tables.blank_effect(id: 3, spell: 1, effect_type: 10, target_flags: 5)
  let cases = [
    #(
      9,
      [heal_at_the_area],
      1,
      True,
      "Crisis Wave's mechanic with a Closest area",
    ),
    #(41, [], 2, True, "Triage's mechanic with a Furthest area"),
    #(9, [], 3, True, "a Random area"),
    #(
      16,
      [],
      1,
      False,
      "a hostile mechanic (Impale, Crush) with no foe row of its own",
    ),
    #(
      9,
      [damage_at_the_area],
      1,
      False,
      "a damage row aimed at the area hits foes",
    ),
    #(
      9,
      [state_at_the_primary_target],
      1,
      False,
      "a crowd-control row aimed at the primary target hits foes",
    ),
    #(
      9,
      [heal_at_the_area],
      5,
      True,
      "Crisis Wave's mechanic with an area ordered by missing health",
    ),
    #(
      9,
      [damage_at_the_area],
      5,
      False,
      "a damage row aimed at the area hits foes at order 5 as at order 1",
    ),
    #(9, [], 4, False, "an area ordered by lowest health is not built"),
    #(9, [], 0, False, "a spell with no area row finds nobody"),
  ]
  list.each(cases, fn(one) {
    let #(flags, effects, target_selection, expected, reason) = one
    assert finds_allies(flags:, effects:, target_selection:) == expected
      as reason
  })
}

/// The heal rows of the tree of the ability whose Spell4 is `spell4_id` and of its alternate
/// (the spell cast under Spell Surge), by row id, with their aim.
fn tree_heals(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(#(Int, spell_plan.Aim)) {
  let assert Ok(row) = spell4.get(tables:, id: Spell4Id(spell4_id))
    as "the ability's Spell4 row is there"
  let assert Ok(ability) =
    spell_plan.in_plans(
      plans: spell_plan.plans_with_later(tables:),
      base: Spell4BaseId(row.spell4_base_id_base_spell),
    )
    as "the plans hold the ability"
  spell_plan.tree_with_alternate(spell: ability)
  |> list.flat_map(fn(spell) {
    list.filter_map(spell.effects, fn(planned) {
      spell_plan.as_heal(kind: planned.kind)
      |> result.map(fn(heal) { #(heal.effect_id.value, heal.aim) })
    })
  })
}

/// The five abilities whose area is a friendly one of an order by distance (Catharsis,
/// Dual Shock, Flash, Emission, Sustain) read their instant heal rows aimed at the caster and
/// the area as aimed at both (`Spell4Effects` 99016, 89663 in Dual Shock's child 40409, 94498,
/// 141384, and Sustain's 99203 and 99208 and those of its Surge alternate, 99236 and 99238: all
/// targetFlags 5, delay 0, no tickTime).
/// Flash's Proxy row 180600 (flags 5) keeps its reading, a child on the caster.
pub fn the_five_abilities_with_a_friendly_area_of_a_built_order_read_their_area_heals_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(
    [
      #(33_270, [99_016]),
      #(70_975, [89_663]),
      #(41_926, [94_498]),
      #(58_841, [141_384]),
      #(43_326, [99_203, 99_208, 99_236, 99_238]),
    ],
    fn(one) {
      let #(spell4_id, row_ids) = one
      let heals = tree_heals(tables:, spell4_id:)
      list.each(row_ids, fn(row_id) {
        assert list.key_find(heals, row_id) == Ok(AimsAtCasterAndArea)
          as {
            "the heal row "
            <> int.to_string(row_id)
            <> " of Spell4 "
            <> int.to_string(spell4_id)
            <> " is aimed at the caster and the area"
          }
      })
    },
  )
  let sources = spell_plan.sources_of(tables:)
  let assert Ok(proxy_row) =
    list.find(spell_plan.effects_of(sources:, spell4_id: 41_926), fn(effect) {
      effect.id == 180_600
    })
    as "Flash's Proxy row 180600 is among its spell's rows"
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  assert spell_plan.read_row(
      tables:,
      sources:,
      place: place_of(41_926),
      effect: proxy_row,
    )
    == Ok(spell_plan.LeftOut(why: spell_plan.ProxyStartsTiersNoChoice))
    as "Flash's Proxy row 180600 (flags 5) is read as it was before an area found allies: left out for its tiers (`spell_plan.gaps` \"Spell areas\"), so a Proxy's allies are not read"
}

/// The Proxy rows of the tree of the ability whose Spell4 is `spell4_id` and of its alternate,
/// by row id, with the unit each starts its child on.
fn tree_proxies(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(#(Int, spell_plan.ProxyTarget)) {
  let assert Ok(row) = spell4.get(tables:, id: Spell4Id(spell4_id))
    as "the ability's Spell4 row is there"
  let assert Ok(ability) =
    spell_plan.in_plans(
      plans: spell_plan.plans_with_later(tables:),
      base: Spell4BaseId(row.spell4_base_id_base_spell),
    )
    as "the plans hold the ability"
  spell_plan.tree_with_alternate(spell: ability)
  |> list.flat_map(fn(spell) {
    list.filter_map(spell.effects, fn(planned) {
      spell_plan.as_proxy(kind: planned.kind)
      |> result.map(fn(proxy) { #(proxy.effect_id.value, proxy.target) })
    })
  })
}

/// The six abilities whose area is ordered by missing health and whose rows are instant heals
/// aimed at the area read those rows as heals aimed at the area: Crisis Wave 41382 (row 93037),
/// Soothe 33140 (78168, 78280, 78282), Vitality Burst 39132 (85507, 85508, 85509, 85526,
/// 85527, 85529) with targetFlags 5, so the caster keeps its bit, and Triage 29888 (141503),
/// Dual Fire 39068 and its Surge alternate (84876, 126516), Regenerative Pulse 39646 (204551
/// and 204560, behind the target gates of type 40, Prerequisite 13986 and 13985: the ally's health
/// percentage, which the caster's picture holds) and its alternate (204570) with targetFlags 4
/// (`table_rows -- Spell4Effects 93037 ... 204570`). Rows that keep today's reading: Triage's
/// HealShields 174070 (delay 10, so not an instant row), and the Proxy rows and the periodic heal 85062 of Mental Boon 33257 and Astral
/// Infusion 35870, whose areas are ordered by health too and whose Proxies start on the caster.
pub fn the_six_abilities_with_a_friendly_area_ordered_by_health_read_their_area_heals_and_the_proxy_ones_stay_as_they_were_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  list.each(
    [
      #(41_382, [93_037], AimsAtCasterAndArea),
      #(33_140, [78_168, 78_280, 78_282], AimsAtCasterAndArea),
      #(
        39_132,
        [85_507, 85_508, 85_509, 85_526, 85_527, 85_529],
        AimsAtCasterAndArea,
      ),
      #(29_888, [141_503], AimsAtArea),
      #(39_068, [84_876, 126_516], AimsAtArea),
      #(39_646, [204_551, 204_560], AimsAtArea),
      #(47_080, [204_570], AimsAtArea),
    ],
    fn(one) {
      let #(spell4_id, row_ids, aim) = one
      let heals = tree_heals(tables:, spell4_id:)
      list.each(row_ids, fn(row_id) {
        assert list.key_find(heals, row_id) == Ok(aim)
          as {
            "the heal row "
            <> int.to_string(row_id)
            <> " of Spell4 "
            <> int.to_string(spell4_id)
            <> " is read aimed at "
            <> string.inspect(aim)
          }
      })
    },
  )
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  list.each(
    [
      #(29_888, 174_070, "Triage's HealShields row has a delay of 10 ms"),
    ],
    fn(one) {
      let #(spell4_id, row_id, reason) = one
      let assert Ok(row) =
        list.find(spell_plan.effects_of(sources:, spell4_id:), fn(effect) {
          effect.id == row_id
        })
        as "the row is among its spell's rows"
      assert spell_plan.read_row(
          tables:,
          sources:,
          place: place_of(spell4_id),
          effect: row,
        )
        == Ok(spell_plan.LeftOut(why: spell_plan.AimedAtOtherUnits))
        as { "row " <> int.to_string(row_id) <> " stays left out: " <> reason }
    },
  )
  assert list.key_find(tree_heals(tables:, spell4_id: 35_870), 85_062)
    == Ok(AimsAtCaster)
    as "Astral Infusion's periodic heal keeps aiming at the caster"
  list.each(
    [
      #(33_257, [76_609, 76_778, 76_779, 76_780, 76_781]),
      #(35_870, [229_155, 229_164]),
    ],
    fn(one) {
      let #(spell4_id, row_ids) = one
      let proxies = tree_proxies(tables:, spell4_id:)
      list.each(row_ids, fn(row_id) {
        assert list.key_find(proxies, row_id) == Ok(spell_plan.OnCaster)
          as {
            "the Proxy row "
            <> int.to_string(row_id)
            <> " of Spell4 "
            <> int.to_string(spell4_id)
            <> " starts its child on the caster"
          }
      })
    },
  )
}

/// Energize's heal row aimed at the caster and the area with no delay: the instant row the
/// strike tells another player (`spell_plan.telling_of`).
fn instant_heal_at_the_area() -> Spell4Effects {
  Spell4Effects(..heal_aimed_at(flags: 5), delay_time: 0)
}

/// A friendly area's heal row is read for the allies only when the strike can check its target
/// apply prerequisite for another player: it knows an ally by its place and its health
/// (`prerequisite.of_struck`, `with_health`), so a gate on the casts held on the unit (types 15, 59,
/// 129) or on its own state (type 1, the level) cannot be told for an ally and the row keeps the
/// caster's own heal, as it did before the area found allies, while a gate on who the unit is (type
/// 39, a player), on its health percentage (type 40) or no gate lets it reach them. Each row is Energize's heal row aimed at the caster
/// and the area (flags 5) in a place that finds allies, behind a Prerequisite of one condition
/// planted for the case: no client row of a friendly area holds a gate the strike can tell.
pub fn a_friendly_area_heal_behind_a_gate_the_strike_cannot_check_for_an_ally_keeps_the_casters_own_heal_test() -> Nil {
  use <- owned_test.run(60_000)
  let place = spell_plan.RowPlace(..spell_tables.pressed, finds_allies: True)
  let aim_of_row_behind = fn(condition_type, comparison, value) {
    use tables <- fixture_tables.added(
      table: "Prerequisite",
      copy_of: 3,
      id: 99_907,
      with: [
        #("prerequisiteTypeId0", Integer(condition_type)),
        #("prerequisiteComparisonId0", Integer(comparison)),
        #("value0", Integer(value)),
      ],
    )
    let effect =
      Spell4Effects(
        ..instant_heal_at_the_area(),
        prerequisite_id_target_apply: 99_907,
      )
    let assert Ok(reading) =
      spell_plan.read_row(
        tables:,
        sources: spell_plan.sources_of(tables:),
        place:,
        effect:,
      )
    let assert [heal] =
      list.filter_map(spell_tables.planned_kinds(reading:), spell_plan.as_heal)
      as "the row is read as one heal"
    heal.aim
  }
  let cases = [
    #(15, 2, 35_023, AimsAtCaster, "the casts held on the unit (type 15)"),
    #(59, 1, 0, AimsAtCaster, "the stack count on the unit (type 59)"),
    #(1, 1, 5, AimsAtCaster, "the unit's own level (type 1)"),
    #(39, 1, 1, AimsAtCasterAndArea, "whether the unit is a player (type 39)"),
    #(
      40,
      6,
      30,
      AimsAtCasterAndArea,
      "the unit's health percentage (type 40), which the picture holds of an ally",
    ),
  ]
  list.each(cases, fn(one) {
    let #(condition_type, comparison, value, expected, reason) = one
    assert aim_of_row_behind(condition_type, comparison, value) == expected
      as { "a heal row at the caster and the area behind a gate on " <> reason }
  })
  let assert Ok(plain) =
    spell_tables.read_row(effect: instant_heal_at_the_area(), place:)
  let assert [heal] =
    list.filter_map(
      spell_tables.planned_kinds(reading: plain),
      spell_plan.as_heal,
    )
  assert heal.aim == AimsAtCasterAndArea
    as "a row behind no gate reaches the allies"
}

/// The six healing potions' heal row 69976 (flags 5, behind the type 15 gate of Spell4 35023:
/// "no live cast of Spell4 35023 has the unit as a target") is read as the caster's own heal in
/// the potion's place, which finds allies (mechanic 7, an area of order 1), so the potions
/// are planned.
pub fn a_healing_potions_area_heal_is_read_as_the_casters_own_heal_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let sources = spell_plan.sources_of(tables:)
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  let place = place_of(35_008)
  assert place.finds_allies as "the potion's area finds allies"
  let assert Ok(row) =
    list.find(spell_plan.effects_of(sources:, spell4_id: 35_008), fn(effect) {
      effect.id == 69_976
    })
    as "row 69976 is among Spell4 35008's rows"
  let assert Ok(reading) =
    spell_plan.read_row(tables:, sources:, place:, effect: row)
    as "the potion's heal row is read, not refused"
  let assert [heal] =
    list.filter_map(spell_tables.planned_kinds(reading:), spell_plan.as_heal)
  assert heal.aim == AimsAtCaster as "the potion heals the caster alone"
}
