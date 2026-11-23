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
////   have no check, so a row behind either is refused at load, naming what is not read.
//// - `Prerequisite.prerequisiteTypeId.37` draws a roll for each test and reads none of the
////   unit's own state, so a row past the caster behind a type 37 condition plans: the
////   client's own type 80 remove 173068 (Spell4 41193, target apply 650) is one.

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
import planted_table
import spell_tables

/// The plan of one client spell, alone.
fn plan_of(spell4_id spell4_id: Int) -> Result(Spell, spell_plan.PlanError) {
  spell_tables.planned_alone(tables: fixture_tables.shared(), spell4_id:)
}

/// The condition of the lasting row of this id in the spell.
fn lasting_condition(
  spell spell: Spell,
  effect_id effect_id: Int,
) -> Condition {
  let assert Ok(row) =
    list.find(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_lasting),
      fn(row) { row.effect_id == Spell4EffectsId(effect_id) },
    )
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
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.pressed,
      effect: row,
    )
    as "a remove behind a target prerequisite of a type the server reads plans"
  let assert spell_plan.Applied(_) = reading
    as "a go applies it: it is no longer held"
  let assert [spell_plan.RemoveEffect(remove:)] =
    spell_tables.planned_kinds(reading:)
  let assert GatedOnTarget(prerequisite:) = remove.condition
    as "the remove keeps its target apply prerequisite"
  assert prerequisite.id(prerequisite) == PrerequisiteId(13_148)
    as "Spell4Effects.144869: prerequisiteIdTargetApply 13148"
}

pub fn target_gate_with_undecoded_type_is_refused_naming_what_it_does_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  assert !prerequisite.is_read(type_id: 12)
    as "Prerequisite 18863 holds types 47 and 12, and the server has not decoded 12"
  let assert Error(error) = plan_of(spell4_id: 45_273)
    as "a lasting row behind an undecoded target prerequisite is refused at load"
  assert error
    == spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: 45_273,
      effect_id: 105_266,
      prerequisite_type: 12,
    )
  let text = spell_plan.describe(error:)
  assert string.contains(text, "12")
    && string.ends_with(text, "which is not decoded")
    as "the refusal names the type and says it is not decoded, with no issue"
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
  assert string.contains(text, "15")
    && string.ends_with(
      text,
      "which reads what the casts held on the creature it strikes hold",
    )
    as "the refusal names the type and says its casts are not read, with no issue"
  let assert Ok(on_the_caster) = plan_of(spell4_id: 30_458)
    as "a row aimed only at the caster reads the caster's own state, so the same type plans"
  let assert GatedOnTarget(prerequisite:) =
    lasting_condition(spell: on_the_caster, effect_id: 55_576)
    as "the row keeps its gate"
  assert prerequisite.id(prerequisite) == PrerequisiteId(15_912)
    as "Spell4Effects.55576: prerequisiteIdTargetApply 15912"
}

pub fn remove_past_the_caster_behind_a_roll_gate_reads_with_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 13148, the gate of Ruin's remove 144869 (aimed at the area),
  // made a type 37 condition (comparison 6, value 50: at most 50 of 100,
  // `Prerequisite.prerequisiteTypeId.37`). That is what the client's own remove 173068
  // (Spell4 41193, target apply 650) is: a type 80 row past the caster behind a roll
  // (`table_rows -- Spell4Effects 173068 -- Prerequisite 650`).
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 13_148, with: [
    #("prerequisiteTypeId0", planted_table.Integer(37)),
    #("prerequisiteComparisonId0", planted_table.Integer(6)),
    #("objectId0", planted_table.Integer(0)),
    #("value0", planted_table.Integer(50)),
  ])
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(144_869))
    as "the client's rows hold Ruin's remove"
  let assert Ok(reading) =
    spell_plan.read_row(
      tables:,
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.pressed,
      effect: row,
    )
    as "a remove past the caster behind a roll plans: the roll reads no state of the unit it reaches"
  let assert spell_plan.Applied(_) = reading
  let assert [spell_plan.RemoveEffect(remove:)] =
    spell_tables.planned_kinds(reading:)
  assert remove.aim == spell_plan.AimsAtArea
  let assert GatedOnTarget(prerequisite:) = remove.condition
    as "the remove keeps its roll gate as its target gate"
  assert prerequisite.id(prerequisite) == PrerequisiteId(13_148)
  assert prerequisite.rolls_needed(prerequisite:) == 1
    as "the gate draws one roll for each unit the remove reaches"
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

const caster_gated_row = 99_914

pub fn caster_gate_with_undecoded_type_is_refused_on_a_lasting_row_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: row 55576 (Spell4 30458, lasting, aimed at the caster, plans) with its target
  // apply 15912 cleared and its caster apply set to 18863, whose type 12 the server has not
  // decoded (`table_rows -- Prerequisite 18863`).
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 55_576,
    id: caster_gated_row,
    with: [
      #("prerequisiteIdTargetApply", planted_table.Integer(0)),
      #("prerequisiteIdCasterApply", planted_table.Integer(18_863)),
    ],
  )
  assert !prerequisite.is_read(type_id: 12)
    as "Prerequisite 18863 holds types 47 and 12, and the server has not decoded 12"
  let assert Error(error) =
    spell_tables.planned_alone(tables:, spell4_id: 30_458)
    as "a lasting row behind an undecoded caster apply prerequisite is refused at load: no go can check it, and a go that cannot tell applies nothing"
  assert error
    == spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: 30_458,
      effect_id: caster_gated_row,
      prerequisite_type: 12,
    )
}

const stealth_row = 99_915

const gain_row = 99_916

pub fn stealth_on_the_caster_behind_a_target_gate_reads_with_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: row 55576 (Spell4 30458, aimed at the caster, plans) made a Stealth row
  // (effectType 83, no delayTime or durationTime, dataBits02 0) behind target apply 903, the
  // gate the client's own caster-aimed Stealth rows 57886 and 115009 hold
  // (`table_rows -- Spell4Effects 57886 115009`). Such a row reaches no other unit, so the
  // gate is checked on the caster.
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 55_576,
    id: stealth_row,
    with: [
      #("effectType", planted_table.Integer(83)),
      #("prerequisiteIdTargetApply", planted_table.Integer(903)),
      #("delayTime", planted_table.Integer(0)),
      #("durationTime", planted_table.Integer(0)),
      #("dataBits02", planted_table.Integer(0)),
    ],
  )
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 30_458)
    as "a stealth row aimed at the caster behind a decoded target prerequisite plans"
  let assert Ok(row) =
    list.find(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_stealth),
      fn(row) { row.effect_id == Spell4EffectsId(stealth_row) },
    )
    as "the plan lists the row"
  let assert GatedOnTarget(prerequisite:) = row.condition
    as "the row keeps its target apply prerequisite as its gate"
  assert prerequisite.id(prerequisite) == PrerequisiteId(903)
}

pub fn gain_on_the_caster_behind_a_target_gate_reads_with_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: row 55576 made a VitalModifier row (effectType 1, vital 6, dataBits02 180,
  // phase flags 1, as Spell4Effects 127603 holds) behind target apply 390, the gate the
  // client's caster-aimed gain 69113 holds (`table_rows -- Spell4Effects 69113`).
  use tables <- fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 55_576,
    id: gain_row,
    with: [
      #("effectType", planted_table.Integer(1)),
      #("prerequisiteIdTargetApply", planted_table.Integer(390)),
      #("dataBits00", planted_table.Integer(6)),
      #("dataBits02", planted_table.Integer(180)),
      #("phaseFlags", planted_table.Integer(1)),
      #("delayTime", planted_table.Integer(0)),
      #("durationTime", planted_table.Integer(0)),
    ],
  )
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 30_458)
    as "a gain aimed at the caster behind a decoded target prerequisite plans"
  let assert Ok(gain) =
    list.find(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_gain),
      fn(gain) { gain.effect_id == Spell4EffectsId(gain_row) },
    )
    as "the plan lists the gain"
  let assert GatedOnTarget(prerequisite:) = gain.condition
    as "the gain keeps its target apply prerequisite as its gate"
  assert prerequisite.id(prerequisite) == PrerequisiteId(390)
}

/// Kept edit: a Prerequisite made one condition of type 28, whether the unit is in combat
/// (comparison 1), which reads the state the unit it is tested on holds itself
/// (`prerequisite.checked_by_creature`).
const in_combat_gate = [
  #("prerequisiteTypeId0", planted_table.Integer(28)),
  #("prerequisiteComparisonId0", planted_table.Integer(1)),
  #("objectId0", planted_table.Integer(0)),
  #("value0", planted_table.Integer(0)),
]

/// The condition of the remove row of this id in the spell.
fn remove_condition(spell spell: Spell, effect_id effect_id: Int) -> Condition {
  let assert Ok(row) =
    list.find(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_remove),
      fn(row) { row.effect_id == Spell4EffectsId(effect_id) },
    )
    as "the plan lists the row among the spell's removes"
  row.condition
}

pub fn remove_past_the_caster_behind_a_creature_state_gate_is_left_to_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 13148, the gate of Ruin's remove 144869 (aimed at the area, so
  // past the caster), made the type 28 condition above.
  use tables <- fixture_tables.changed(
    table: "Prerequisite",
    id: 13_148,
    with: in_combat_gate,
  )
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 38_841)
    as "a remove past the caster behind a gate that reads the unit's own state plans"
  assert remove_condition(spell:, effect_id: 144_869) == spell_plan.Always
    as "the cast rule checks no gate of the row: the creature the strike names does"
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(144_869))
    as "the client's rows hold Ruin's remove"
  let assert [gate] = spell.struck_gates
    as "the spell tells its one gated row's gate to the creatures its strike reaches"
  assert gate.effect_id == Spell4EffectsId(144_869)
  assert prerequisite.id(gate.prerequisite) == PrerequisiteId(13_148)
    as "Spell4Effects.144869: prerequisiteIdTargetApply 13148"
  assert gate.aim == spell_plan.AimsAtArea
    as "Spell4Effects.144869: targetFlags 4, the area"
  assert gate.phase_flags == row.phase_flags
  assert gate.tag == spell_plan.tag_of(effect: row)
}

pub fn gate_mixing_creature_state_with_cast_state_stays_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 13148 made two conditions, type 15 (comparison 1), which reads
  // the casts held on the unit, and type 28 (comparison 1). The creature checks no row that
  // reads the casts held on it, since a creature holds none of them.
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 13_148, with: [
    #("prerequisiteTypeId0", planted_table.Integer(15)),
    #("prerequisiteComparisonId0", planted_table.Integer(1)),
    #("objectId0", planted_table.Integer(0)),
    #("value0", planted_table.Integer(0)),
    #("prerequisiteTypeId1", planted_table.Integer(28)),
    #("prerequisiteComparisonId1", planted_table.Integer(1)),
    #("objectId1", planted_table.Integer(0)),
    #("value1", planted_table.Integer(0)),
  ])
  assert spell_tables.planned_alone(tables:, spell4_id: 38_841)
    == Error(spell_plan.TargetPrerequisiteReadsStruckUnit(
      spell4_id: 38_841,
      effect_id: 144_869,
      prerequisite_type: 15,
    ))
    as "a remove behind a gate the creature cannot check whole stays refused, naming the cast-reading type"
}

pub fn row_aimed_at_the_caster_keeps_a_creature_state_gate_with_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 15912, the gate of row 55576 (Spell4 30458, aimed at the
  // caster), made the type 28 condition above.
  use tables <- fixture_tables.changed(
    table: "Prerequisite",
    id: 15_912,
    with: in_combat_gate,
  )
  let assert Ok(spell) = spell_tables.planned_alone(tables:, spell4_id: 30_458)
    as "a row aimed at the caster behind a gate on the unit's own state plans"
  let assert GatedOnTarget(prerequisite:) =
    lasting_condition(spell:, effect_id: 55_576)
    as "the cast rule checks the gate against the caster, whose state it holds"
  assert prerequisite.id(prerequisite) == PrerequisiteId(15_912)
  assert spell.struck_gates == []
    as "no creature is asked about a row that reaches only the caster"
}

pub fn remove_aimed_at_the_caster_and_past_it_behind_a_creature_state_gate_stays_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 13148 made the type 28 condition above, and remove 144869
  // aimed by targetFlags 3, the caster and the primary target. One condition covers both
  // units, and the caster cannot check the unit past it.
  use tables <- fixture_tables.changed(
    table: "Prerequisite",
    id: 13_148,
    with: in_combat_gate,
  )
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(144_869))
    as "the client's rows hold Ruin's remove"
  assert spell_plan.read_row(
      tables:,
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.pressed,
      effect: spell4_effects.Spell4Effects(..row, target_flags: 3),
    )
    == Error(spell_plan.TargetPrerequisiteReadsStruckUnit(
      spell4_id: 38_841,
      effect_id: 144_869,
      prerequisite_type: 28,
    ))
}

pub fn remove_on_the_primary_target_of_a_press_behind_a_creature_state_gate_stays_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  // Kept edit: Prerequisite 13148 made the type 28 condition above, and remove 144869
  // aimed by targetFlags 2, the primary target. A press has the caster itself as its
  // primary target, which no strike names; a child cast on a struck unit has that unit.
  use tables <- fixture_tables.changed(
    table: "Prerequisite",
    id: 13_148,
    with: in_combat_gate,
  )
  let assert Ok(row) = spell4_effects.get(tables:, id: Spell4EffectsId(144_869))
    as "the client's rows hold Ruin's remove"
  let on_the_primary_target =
    spell4_effects.Spell4Effects(..row, target_flags: 2)
  assert spell_plan.read_row(
      tables:,
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.pressed,
      effect: on_the_primary_target,
    )
    == Error(spell_plan.TargetPrerequisiteReadsStruckUnit(
      spell4_id: 38_841,
      effect_id: 144_869,
      prerequisite_type: 28,
    ))
    as "in a press the row would be checked on no unit, so the load refuses it"
  let assert Ok(reading) =
    spell_plan.read_row(
      tables:,
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.started_on_each_struck(
        spell4_id: 1,
        proxy_effect_id: 2,
      ),
      effect: on_the_primary_target,
    )
    as "in a child started on a struck unit the primary target is that creature"
  let assert spell_plan.Applied(_) = reading
  let assert [spell_plan.RemoveEffect(remove:)] =
    spell_tables.planned_kinds(reading:)
  assert remove.condition == spell_plan.Always
}

pub fn gate_with_a_creature2_condition_is_checked_by_the_creature_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 27656 (`table_rows -- Spell4Effects spellId=27656`): its crowd control row 49004
  // (effectType 4, targetFlags 4, phaseFlags 1) has target apply 6780 = type 4, comparison 1,
  // value 171, and type 38, comparison 2, value 18721. The creature holds its faction and its
  // Creature2 row, so it checks the whole gate.
  let assert Ok(spell) = plan_of(spell4_id: 27_656)
    as "a spell whose row is gated on a faction and a Creature2 row plans"
  let assert Ok(gate) =
    list.find(spell.struck_gates, fn(gate) {
      gate.effect_id == Spell4EffectsId(49_004)
    })
    as "the strike carries the gate of row 49004 to the creatures it reaches"
  assert prerequisite.id(gate.prerequisite) == PrerequisiteId(6780)
    as "Spell4Effects.49004: prerequisiteIdTargetApply 6780"
  assert gate.aim == spell_plan.AimsAtArea
    as "Spell4Effects.49004: targetFlags 4, the area"
}
