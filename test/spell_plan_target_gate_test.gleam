//// The plan's rows behind a target apply prerequisite (`genesis_prime/game/spell_plan`
//// `Condition`). Expected values come from these places.
//// - The client's rows (`table_rows -- Spell4Effects 144869 105266 182739 55576 91018 111129`
////   and `-- Prerequisite 13148 18863 20868 15912 11311 903 20271`), kept in the fixture:
////   - Ruin's remove (Spell4 38841, row 144869): effectType 80, targetFlags 4, dataBits00 3
////     and dataBits01 23183, phaseFlags -1, target apply 13148 = one condition of type 130
////     (comparison 1, object 464, value 38803).
////   - Row 105266 (Spell4 45273): effectType 81, targetFlags 4, target apply 18863 = a
////     condition of type 47 (comparison 1, value 15408) and one of type 12 (comparison 1).
////   - Row 182739 (Spell4 71280): effectType 81, targetFlags 6, target apply 20868 = type 15,
////     comparison 1, value 49303.
////   - Row 55576 (Spell4 30458): effectType 81, targetFlags 1, target apply 15912 = type 15,
////     comparison 2, value 42007.
////   - Row 91018 (Spell4 38784): effectType 81, targetFlags 1, caster apply 11311 and target
////     apply 11311 (flags 1, two conditions of type 109).
////   - Row 111129 (Spell4 47328): effectType 81, targetFlags 4, caster apply 903 (type 28)
////     and target apply 20271 (type 38, value 49550).
//// - `Spell4Effects.prerequisiteIdTargetApply`: its first unit is the unit the effect
////   reaches and its second unit the caster; the types whose reading the server has not
////   decoded (`prerequisite.is_read`) and the types that read a struck creature's own state
////   have no check, so a row behind either is refused at load, naming the issue that will
////   read it.

import fixture_tables
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Condition, type Spell, GatedOnCasterAndTarget, GatedOnTarget,
}
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/string
import owned_test
import spell_tables

/// The plan of one client spell, alone.
fn plan_of(spell4_id spell4_id: Int) -> Result(Spell, spell_plan.PlanError) {
  let tables = fixture_tables.shared()
  spell_plan.spell_alone(
    tables:,
    sources: spell_plan.sources_of(tables:),
    spell4_id:,
    chain: [],
  )
}

/// The condition of the lasting row of this id in the spell.
fn lasting_condition(
  spell spell: Spell,
  effect_id effect_id: Int,
) -> Condition {
  let assert Ok(row) =
    list.find(spell.lasting, fn(row) {
      row.effect_id == Spell4EffectsId(effect_id)
    })
    as "the plan lists the row among the spell's lasting rows"
  row.condition
}

pub fn remove_behind_target_gate_reads_with_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(144_869))
    as "the client's rows hold Ruin's remove"
  let assert Ok(reading) =
    spell_plan.read_row(
      tables:,
      spell_groups: spell_plan.spell_groups(tables:),
      place: spell_tables.pressed,
      effect: row,
    )
    as "a remove behind a target prerequisite of a type the server reads plans"
  let assert spell_plan.Applied(spell_plan.PlannedRemove(remove:)) = reading
    as "a go applies it: it is no longer held"
  let assert GatedOnTarget(prerequisite:) = remove.condition
    as "the remove keeps its target apply prerequisite"
  assert prerequisite.id(prerequisite) == PrerequisiteId(13_148)
    as "Spell4Effects.144869: prerequisiteIdTargetApply 13148"
}

pub fn target_gate_with_undecoded_type_is_refused_naming_its_issue_test() -> Nil {
  use <- owned_test.run(60_000)
  assert !prerequisite.is_read(type_id: 12)
    as "Prerequisite 18863 holds types 47 and 12, and the server has not decoded 12"
  let assert Error(error) = plan_of(spell4_id: 45_273)
    as "a lasting row behind an undecoded target prerequisite is refused at load"
  assert error
    == spell_plan.TargetPrerequisiteNotRead(
      spell4_id: 45_273,
      effect_id: 105_266,
      prerequisite_type: 12,
    )
  let text = spell_plan.describe(error:)
  assert string.contains(text, "12") && string.contains(text, "#818")
    as "the refusal names the type and the issue that will read it"
}

pub fn target_gate_reading_struck_state_is_refused_past_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(error) = plan_of(spell4_id: 71_280)
    as "a row aimed past the caster behind a type 15 target prerequisite is refused"
  assert error
    == spell_plan.TargetPrerequisiteReadsStruckUnit(
      spell4_id: 71_280,
      effect_id: 182_739,
      prerequisite_type: 15,
    )
  let text = spell_plan.describe(error:)
  assert string.contains(text, "15") && string.contains(text, "#817")
    as "the refusal names the type and the issue that will read it"
  let assert Ok(on_the_caster) = plan_of(spell4_id: 30_458)
    as "a row aimed only at the caster reads the caster's own state, so the same type plans"
  let assert GatedOnTarget(prerequisite:) =
    lasting_condition(spell: on_the_caster, effect_id: 55_576)
    as "the row keeps its gate"
  assert prerequisite.id(prerequisite) == PrerequisiteId(15_912)
    as "Spell4Effects.55576: prerequisiteIdTargetApply 15912"
}

pub fn row_with_caster_and_target_gates_keeps_both_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(both_same) = plan_of(spell4_id: 38_784) as "row 91018 plans"
  let assert GatedOnCasterAndTarget(caster:, target:) =
    lasting_condition(spell: both_same, effect_id: 91_018)
    as "a row with both apply prerequisites keeps both"
  assert list.map(caster, prerequisite.id) == [PrerequisiteId(11_311)]
    as "Spell4Effects.91018: prerequisiteIdCasterApply 11311"
  assert prerequisite.id(target) == PrerequisiteId(11_311)
    as "Spell4Effects.91018: prerequisiteIdTargetApply 11311"
  let assert Ok(area) = plan_of(spell4_id: 47_328) as "row 111129 plans"
  let assert GatedOnCasterAndTarget(caster:, target:) =
    lasting_condition(spell: area, effect_id: 111_129)
    as "an area row with both apply prerequisites keeps both"
  assert list.map(caster, prerequisite.id) == [PrerequisiteId(903)]
    as "Spell4Effects.111129: prerequisiteIdCasterApply 903"
  assert prerequisite.id(target) == PrerequisiteId(20_271)
    as "Spell4Effects.111129: prerequisiteIdTargetApply 20271"
}
