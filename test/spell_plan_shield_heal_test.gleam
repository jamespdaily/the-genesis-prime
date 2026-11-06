//// The shield heals and shield overloads of the plan (`genesis_prime/game/spell_plan`
//// `ShieldHeal`, `TickingShieldHeal`, `Lasting`, `genesis_prime/game/effect_kind`).
//// Expected values come from these places.
//// - `Spell4Effects.effectType.118`: a HealShields row restores shield to the unit it
////   lands on, by the amount of `0x140565600`'s formula; its columns are the Medic's
////   Energize 228914 (targetFlags 1, delayTime 10, dataBits00 1.0, dataBits01 0,
////   parameterType00 22 with value 0.3, phaseFlags -1, no tickTime), the Warrior's
////   Onslaught row 210834 (tickTime 1000, durationTime 8000, flags 16, dataBits04 1,
////   parameterType00 16 with value 0.125) and the Medic's Hypercharge row 146893
////   (targetFlags 4) (`table_rows -- Spell4Effects spellId=69450`, `=46867`, `=60718`).
//// - `0x140566ad0` and `0x140566d40`: the parameter types the formula reads; the
////   attributes (1 to 5, 11) and the passed-in value (18) the server does not read for an
////   effect on its caster.
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

import client_tables
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  AimsAtArea, AimsAtCaster, AimsAtPrimaryTarget, Always, Lasting, OnCaster,
  OnEachStruck, ShieldHeal, TickingShieldHeal,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/int
import gleam/list
import owned_test
import unitest

/// 1.0 as 32 float bits.
const one_as_float_bits = 1_065_353_216

/// A row of a spell, in memory, with every column 0 but its id, spell, type, aim and
/// phases (every one).
fn blank(
  id id: Int,
  spell spell: Int,
  effect_type effect_type: Int,
  target_flags target_flags: Int,
) -> Spell4Effects {
  Spell4Effects(
    id:,
    spell_id: spell,
    target_flags:,
    effect_type:,
    damage_type: 0,
    delay_time: 0,
    tick_time: 0,
    duration_time: 0,
    flags: 0,
    data_bits00: 0,
    data_bits01: 0,
    data_bits02: 0,
    data_bits03: 0,
    data_bits04: 0,
    data_bits05: 0,
    data_bits06: 0,
    data_bits07: 0,
    data_bits08: 0,
    data_bits09: 0,
    innate_cost_per_tick_type0: 0,
    innate_cost_per_tick_type1: 0,
    innate_cost_per_tick0: 0,
    innate_cost_per_tick1: 0,
    emm_comparison: 0,
    emm_value: 0,
    threat_multiplier: 0.0,
    spell4_effect_group_list_id: 0,
    prerequisite_id_caster_apply: 0,
    prerequisite_id_target_apply: 0,
    prerequisite_id_caster_persistence: 0,
    prerequisite_id_target_persistence: 0,
    prerequisite_id_target_suspend: 0,
    parameter_type00: 0,
    parameter_type01: 0,
    parameter_type02: 0,
    parameter_type03: 0,
    parameter_value00: 0.0,
    parameter_value01: 0.0,
    parameter_value02: 0.0,
    parameter_value03: 0.0,
    phase_flags: -1,
    order_index: 0,
  )
}

/// Energize's row 228914 as the client holds it.
fn energize_row() -> Spell4Effects {
  Spell4Effects(
    ..blank(id: 228_914, spell: 69_450, effect_type: 118, target_flags: 1),
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
    ..blank(id: 210_834, spell: 46_867, effect_type: 118, target_flags: 1),
    tick_time: 1000,
    duration_time: 8000,
    flags: 16,
    data_bits00: one_as_float_bits,
    data_bits04: 1,
    parameter_type00: 16,
    parameter_value00: 0.125,
  )
}

/// The condition of every row: none, since each row's gate is read from the tables.
fn no_gate(_effect: Spell4Effects) -> Result(spell_plan.Condition, a) {
  Ok(Always)
}

fn heals_of(
  effects effects: List(Spell4Effects),
) -> List(spell_plan.ShieldHeal) {
  let assert Ok(heals) =
    spell_plan.shield_heals_in(spell4_id: 69_450, effects:, condition: no_gate)
    as "the rows are read"
  heals
}

fn heal_ids(heals heals: List(spell_plan.ShieldHeal)) -> List(Int) {
  list.map(heals, fn(heal) { heal.effect_id.value })
}

// ---- the rows of the plan ----

pub fn a_heal_shields_row_aimed_at_the_caster_is_a_shield_heal_with_its_formula_delay_and_phases_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.shield_heal_of(
      spell4_id: 69_450,
      effect: energize_row(),
      condition: Always,
    )
    == Ok(ShieldHeal(
      effect_id: Spell4EffectsId(228_914),
      phase_flags: -1,
      aim: AimsAtCaster,
      condition: Always,
      tag: spend.EqualTo(value: 0),
      formula: Formula(multiplier: 1.0, base: 0, parameters: [
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
    spell_plan.shield_heal_of(
      spell4_id: 69_450,
      effect: heal_aimed_at(flags: 2),
      condition: Always,
    )
  assert heal.aim == AimsAtPrimaryTarget
    as "targetFlags 2 is the primary target, which the target of a cast on the caster is"
  assert spell_plan.proxy_heals_read(
      spell4_id: 69_450,
      proxy_effect_id: 228_915,
      target: OnCaster,
      heals: [heal],
    )
    == Ok(Nil)
    as "a child a Proxy aimed at the caster starts is cast on the caster: spell_plan.target_of starts flags 1 and 2 there"
}

pub fn a_heal_shields_row_aimed_at_the_primary_target_of_a_child_on_each_struck_unit_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(heal) =
    spell_plan.shield_heal_of(
      spell4_id: 60_718,
      effect: Spell4Effects(
        ..heal_aimed_at(flags: 2),
        id: 146_893,
        spell_id: 60_718,
      ),
      condition: Always,
    )
  assert spell_plan.proxy_heals_read(
      spell4_id: 69_450,
      proxy_effect_id: 228_915,
      target: OnEachStruck,
      heals: [heal],
    )
    == Error(spell_plan.ShieldHealOnStruckUnit(
      spell4_id: 69_450,
      proxy_effect_id: 228_915,
      effect_id: 146_893,
    ))
    as "the child's primary target is a struck unit, and a shield heal on one is not built"
  let assert Ok(on_the_caster) =
    spell_plan.shield_heal_of(
      spell4_id: 60_718,
      effect: heal_aimed_at(flags: 1),
      condition: Always,
    )
  assert spell_plan.proxy_heals_read(
      spell4_id: 69_450,
      proxy_effect_id: 228_915,
      target: OnEachStruck,
      heals: [on_the_caster],
    )
    == Ok(Nil)
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
      TickingShieldHeal(
        effect_id: Spell4EffectsId(210_834),
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

pub fn a_heal_shields_row_with_a_parameter_the_caster_formula_does_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([3, 11, 18], fn(kind) {
    let row =
      Spell4Effects(..energize_row(), id: 99_118, parameter_type00: kind)
    assert spell_plan.shield_heal_of(
        spell4_id: 69_450,
        effect: row,
        condition: Always,
      )
      == Error(spell_plan.ShieldHealParameterNotRead(
        spell4_id: 69_450,
        effect_id: 99_118,
        parameter_kind: kind,
      ))
      as {
        "0x140565600: type "
        <> int.to_string(kind)
        <> " is an attribute or the passed-in value, which an effect on its caster does not read"
      }
  })
  list.each(
    [7, 8, 10, 12, 13, 14, 15, 16, 17, 19, 21, 22, 23, 25, 26],
    fn(kind) {
      let row =
        Spell4Effects(..energize_row(), id: 99_119, parameter_type00: kind)
      let assert Ok(ShieldHeal(..)) =
        spell_plan.shield_heal_of(
          spell4_id: 69_450,
          effect: row,
          condition: Always,
        )
        as { "0x140566ad0 reads type " <> int.to_string(kind) }
    },
  )
  let not_a_number =
    Spell4Effects(..energize_row(), id: 99_120, data_bits00: 0x7F800000)
  assert spell_plan.shield_heal_of(
      spell4_id: 69_450,
      effect: not_a_number,
      condition: Always,
    )
    == Error(spell_plan.ShieldHealNumberNotFinite(
      spell4_id: 69_450,
      effect_id: 99_120,
    ))
    as "dataBits00 is a 32-bit float: 0x7F800000 is infinity"
}

pub fn a_shield_overload_row_aimed_at_the_area_is_a_lasting_row_on_each_struck_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let meltdown =
    Spell4Effects(
      ..blank(id: 147_229, spell: 60_796, effect_type: 64, target_flags: 4),
      duration_time: 4000,
    )
  let assert Ok(lasting) =
    spell_plan.lasting_in(
      spell4_id: 60_796,
      effects: [meltdown],
      condition: no_gate,
    )
  assert lasting
    == [
      Lasting(
        effect_id: Spell4EffectsId(147_229),
        phase_flags: -1,
        aim: AimsAtArea,
        row: LastingRow(delay_ms: 0, duration_ms: 4000, until_removed: False),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "row 147229: aimed at the area, 4000 ms, no delay"
  let assert Ok(left_out) =
    spell_plan.lasting_in(
      spell4_id: 60_796,
      effects: [
        Spell4Effects(..meltdown, id: 1, target_flags: 1),
        Spell4Effects(..meltdown, id: 2, target_flags: 2),
      ],
      condition: no_gate,
    )
  assert left_out == []
    as "35 rows aim at the caster or the primary target, whose shield hold at 0 is not built"
}

// ---- the kinds ----

pub fn effect_kind_reads_heal_shields_for_the_caster_and_shield_overload_for_the_area_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 118) == effect_kind.ShieldHeal
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

// ---- the client's tables ----

/// The Spell4 `spell4_id` of the tree of the innate whose Spell4Base is `base`.
fn planned(base base: Int, spell4_id spell4_id: Int) -> spell_plan.Spell {
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(innate) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
    as "the plans hold the innate"
  let assert Ok(spell) =
    list.find(
      spell_plan.tree(spell: innate, started: fn(_) { True }),
      fn(spell) { spell.spell4_id.value == spell4_id },
    )
    as "the innate's tree holds the spell"
  spell
}

pub fn the_plans_hold_energizes_shield_heal_the_warriors_ticking_row_and_meltdowns_overload_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert [ShieldHeal(effect_id: Spell4EffectsId(228_914), delay_ms: 10, ..)] =
    planned(base: 46_615, spell4_id: 69_450).shield_heals
    as "Spell4Effects spellId=69450: 228914 is the Medic's only shield heal on the caster"
  let assert [
    TickingShieldHeal(
      effect_id: Spell4EffectsId(210_834),
      tick_ms: 1000,
      duration_ms: 8000,
      ..,
    ),
  ] = planned(base: 30_828, spell4_id: 46_867).shield_heals
    as "Spell4Effects spellId=46867: 210834, held and not applied"
  assert planned(base: 46_615, spell4_id: 60_718).shield_heals == []
    as "Spell4Effects spellId=60718: 146893 has targetFlags 4, aimed at other units, so it is left out"
  let assert [Lasting(effect_id: Spell4EffectsId(147_229), aim: AimsAtArea, ..)] =
    list.filter(planned(base: 46_615, spell4_id: 60_796).lasting, fn(row) {
      row.effect_id.value == 147_229
    })
    as "Spell4Effects spellId=60796: 147229, a ShieldOverload aimed at the area, is a lasting row"
  Nil
}
