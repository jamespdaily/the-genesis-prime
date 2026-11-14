//// The heals and shield overloads of the plan (`genesis_prime/game/spell_plan`
//// `Heal`, `TickingHeal`, `Lasting`, `genesis_prime/game/effect_kind`).
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
////   passed-in value (18) the server does not read for an effect on its caster, and 6 and
////   9 add 0 (`Spell4Effects.parameterType.6_9`). Row 94299 (Esper - Tech - Rank 3 -
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
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  AimedAtOtherUnits, AimsAtArea, AimsAtCaster, AimsAtPrimaryTarget, Always,
  Applied, Heal, Held, Lasting, LeftOut, PlannedHeal, PlannedLasting,
  ReadByActivation, ReadByArea, TickingHeal,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import owned_test
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
  |> list.filter_map(fn(reading) {
    case reading {
      Ok(Applied(PlannedHeal(heal:))) | Ok(Held(PlannedHeal(heal:))) -> Ok(heal)
      Ok(Applied(..))
      | Ok(Held(..))
      | Ok(LeftOut(..))
      | Ok(ReadByArea)
      | Ok(ReadByActivation) -> Error(Nil)
      Error(error) ->
        panic as { "the row is refused: " <> spell_plan.describe(error:) }
    }
  })
}

fn heal_ids(heals heals: List(spell_plan.Heal)) -> List(Int) {
  list.map(heals, fn(heal) { heal.effect_id.value })
}

// ---- the rows of the plan ----

pub fn a_heal_shields_row_aimed_at_the_caster_is_a_shield_heal_with_its_formula_delay_and_phases_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.heal_of(
      spell4_id: 69_450,
      effect: energize_row(),
      condition: Always,
    )
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
  let assert Ok(heal) =
    spell_plan.heal_of(
      spell4_id: 69_450,
      effect: heal_aimed_at(flags: 2),
      condition: Always,
    )
  assert heal.aim == AimsAtPrimaryTarget
    as "targetFlags 2 is the primary target, which the target of a cast on the caster is"
  assert spell_tables.read_row(
      effect: heal_aimed_at(flags: 2),
      place: spell_tables.pressed,
    )
    == Ok(Applied(PlannedHeal(heal)))
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

pub fn a_heal_shields_row_aimed_only_at_other_units_is_left_out_and_one_with_the_caster_bit_keeps_its_caster_part_test() -> Nil {
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
  assert list.map(heals, fn(heal) { heal.aim }) == [AimsAtCaster, AimsAtCaster]
    as "the caster part only"
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
        tick_ms: 1000,
        duration_ms: 8000,
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
  let assert Ok(Heal(vital: effect_kind.Shield, ..)) =
    spell_plan.heal_of(spell4_id: 41_868, effect: row, condition: Always)
    as "Esper - Tech - Rank 3 - Shield Heal Proc: Technology (kind 3) x 1.5 is read for an effect on its caster"
  Nil
}

pub fn a_heal_shields_row_with_a_parameter_the_caster_formula_does_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([18], fn(kind) {
    let row =
      Spell4Effects(..energize_row(), id: 99_118, parameter_type00: kind)
    assert spell_plan.heal_of(spell4_id: 69_450, effect: row, condition: Always)
      == Error(spell_plan.HealParameterNotRead(
        spell4_id: 69_450,
        effect_id: 99_118,
        parameter_kind: kind,
      ))
      as {
        "0x140565600: type "
        <> int.to_string(kind)
        <> " is the passed-in value, which an effect on its caster does not read"
      }
  })
  list.each(
    [
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 21, 22, 23,
      25, 26,
    ],
    fn(kind) {
      let row =
        Spell4Effects(..energize_row(), id: 99_119, parameter_type00: kind)
      let assert Ok(Heal(..)) =
        spell_plan.heal_of(spell4_id: 69_450, effect: row, condition: Always)
        as {
          "0x140566ad0 or 0x140566d40 reads type "
          <> int.to_string(kind)
          <> ", or its default adds 0 for 6 and 9"
        }
    },
  )
  let not_a_number =
    Spell4Effects(..energize_row(), id: 99_120, data_bits00: 0x7F800000)
  assert spell_plan.heal_of(
      spell4_id: 69_450,
      effect: not_a_number,
      condition: Always,
    )
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
          PlannedLasting(Lasting(
            effect_id: Spell4EffectsId(147_229),
            phase_flags: -1,
            aim: AimsAtArea,
            row: LastingRow(
              delay_ms: 0,
              duration_ms: 4000,
              until_removed: False,
            ),
            condition: Always,
            tag: spend.EqualTo(value: 0),
          )),
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
  let struck = spell_plan.struck_unit_children(effects: [proxy, heal])
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
  let assert Ok(Applied(PlannedHeal(on_the_caster))) =
    spell_tables.read_row(
      effect: Spell4Effects(..heal, target_flags: 1),
      place:,
    )
    as "a row that includes the caster heals the caster in a struck child too"
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
        PlannedHeal(Heal(
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
  let assert Ok(Applied(PlannedHeal(heal))) =
    spell_tables.read_row(effect: row, place: spell_tables.pressed)
    as "row 94498 is read"
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

pub fn a_heal_row_with_a_tick_time_is_held_test() -> Nil {
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
    == Ok(
      Held(
        PlannedHeal(TickingHeal(
          effect_id: Spell4EffectsId(80_077),
          vital: effect_kind.Health,
          phase_flags: -1,
          aim: AimsAtPrimaryTarget,
          condition: Always,
          tag: spend.EqualTo(value: 0),
          tick_ms: 1000,
          duration_ms: 0,
        )),
      ),
    )
    as "row 80077: tickTime 1000 makes it a periodic heal, held and not applied (a later step ticks it)"
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
  assert spell_plan.heal_of(
      spell4_id: 34_985,
      effect: passed_in,
      condition: Always,
    )
    == Error(spell_plan.HealParameterNotRead(
      spell4_id: 34_985,
      effect_id: 69_917,
      parameter_kind: 18,
    ))
    as "row 69917: parameter 18 is the value passed in, which an effect on its caster does not read (0x140565600)"
  let not_a_number =
    Spell4Effects(..mind_over_body_row(), data_bits00: 0x7F800000)
  assert spell_plan.heal_of(
      spell4_id: 32_820,
      effect: not_a_number,
      condition: Always,
    )
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
    as "a row that includes the caster heals the caster, whichever unit the child is cast on"
}

// ---- the client's tables ----

pub fn the_plans_hold_energizes_shield_heal_the_warriors_ticking_row_and_meltdowns_overload_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert [Heal(effect_id: Spell4EffectsId(228_914), delay_ms: 10, ..)] =
    cast_support.planned_spell(base: 46_615, spell4_id: 69_450).heals
    as "Spell4Effects spellId=69450: 228914 is the Medic's only shield heal on the caster"
  let assert [
    TickingHeal(
      effect_id: Spell4EffectsId(210_834),
      tick_ms: 1000,
      duration_ms: 8000,
      ..,
    ),
  ] = cast_support.planned_spell(base: 30_828, spell4_id: 46_867).heals
    as "Spell4Effects spellId=46867: 210834, held and not applied"
  assert cast_support.planned_spell(base: 46_615, spell4_id: 60_718).heals == []
    as "Spell4Effects spellId=60718: 146893 has targetFlags 4, aimed at other units, so it is left out"
  let assert [Lasting(effect_id: Spell4EffectsId(147_229), aim: AimsAtArea, ..)] =
    list.filter(
      cast_support.planned_spell(base: 46_615, spell4_id: 60_796).lasting,
      fn(row) { row.effect_id.value == 147_229 },
    )
    as "Spell4Effects spellId=60796: 147229, a ShieldOverload aimed at the area, is a lasting row"
  Nil
}
