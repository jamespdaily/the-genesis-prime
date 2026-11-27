//// The NpcExecutionDelay rows of the plan (`genesis_prime/shared/spell_plan` `Delay`,
//// `genesis_prime/shared/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.35`: the columns of the client's rows (`table_rows --
////   Spell4Effects effectType=35`, 3288 rows): 131968 (Spell4 55317, targetFlags 1, delayTime
////   0, durationTime 1000, phaseFlags 0xffff0002, which names go 1 of the spell's two gos);
////   19 rows are aimed at the target (2) and 5 at the area (4); 109 of the 3264 aimed at the
////   caster have a durationTime of 0.
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the area.
//// - `Spell4Effects.phaseFlags`: bit n is phase n; a row of 0 is selected by no phase.

import fixture_tables
import genesis_prime/shared/effect_kind
import genesis_prime/shared/spell_plan.{Delay}
import genesis_prime/shared/spend
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/option.{None}
import owned_test
import spell_tables

/// What the plan makes of Spell4 55317, Earthen Roar tier 2, over the client's rows.
fn earthen_roar() -> spell_plan.Spell {
  let tables = fixture_tables.shared()
  let assert Ok(spell) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id: 55_317,
      chain: [],
    )
    as "the client's rows plan Spell4 55317"
  spell
}

/// What the plan makes of a type 35 row in memory, aimed by `target_flags`, with
/// this duration and phases: every other column 0.
fn reading_of(
  target_flags target_flags: Int,
  duration_ms duration_ms: Int,
  phase_flags phase_flags: Int,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  spell_tables.read_row(
    effect: spell4_effects.Spell4Effects(
      ..spell_tables.blank_effect(
        id: 99_035,
        spell: 1,
        effect_type: 35,
        target_flags:,
      ),
      duration_time: duration_ms,
      phase_flags:,
    ),
    place: spell_tables.pressed,
  )
}

pub fn a_type_35_row_aimed_at_the_caster_is_read_with_its_phases_and_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = earthen_roar()
  assert spell_plan.payloads(spell:, as_kind: spell_plan.as_delay)
    == [
      Delay(
        effect_id: Spell4EffectsId(131_968),
        phase_flags: -65_534,
        delay_ms: 0,
        duration_ms: 1000,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "Spell4Effects 131968: delayTime 0, durationTime 1000, phaseFlags 0xffff0002, emmComparison 0 and emmValue 0 as the tag"
  assert spell_plan.in_phase(
      spell:,
      phase: 1,
      spent: None,
      as_kind: spell_plan.as_delay,
    )
    != []
    as "bit 1 of the flags names go 1"
  assert spell_plan.in_phase(
      spell:,
      phase: 0,
      spent: None,
      as_kind: spell_plan.as_delay,
    )
    == []
    as "bit 0 is clear: the row does not apply at go 0"
  assert effect_kind.is_read(effect_type: 35)
    && effect_kind.is_row_read(effect_type: 35, target_flags: 1)
    as "type 35 is read for a row aimed at the caster alone"
}

pub fn a_type_35_row_aimed_at_another_unit_or_with_no_duration_is_left_out_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  assert reading_of(target_flags: 2, duration_ms: 1000, phase_flags: 1)
    == Ok(spell_plan.LeftOut(why: spell_plan.DelayOnAnotherUnit))
    as "19 rows are aimed at the target"
  assert reading_of(target_flags: 4, duration_ms: 1000, phase_flags: 1)
    == Ok(spell_plan.LeftOut(why: spell_plan.DelayOnAnotherUnit))
    as "5 rows are aimed at the area"
  assert reading_of(target_flags: 3, duration_ms: 1000, phase_flags: 1)
    == Ok(spell_plan.LeftOut(why: spell_plan.DelayOnAnotherUnit))
    as "a row aimed at the caster and another unit holds no other unit still"
  assert reading_of(target_flags: 1, duration_ms: 0, phase_flags: 1)
    == Ok(spell_plan.LeftOut(why: spell_plan.DelayHasNoDuration))
    as "109 rows aimed at the caster have no duration: a hold of nothing"
  assert !effect_kind.is_row_read(effect_type: 35, target_flags: 2)
    as "a row aimed at another unit is not read"
}
