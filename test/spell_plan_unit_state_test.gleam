//// The unit states of the plan (`genesis_prime/game/spell_plan` `UnitState`,
//// `genesis_prime/game/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.15`: the columns of the client's rows (`table_rows --
////   Spell4Effects effectType=15`): 64365 (Spell4 32683 "Stun/Immune - 8 seconds", state 6,
////   targetFlags 2, durationTime 8500, phaseFlags 1), 204411 (Spell4 48565, state 6,
////   targetFlags 4, delayTime 500, durationTime 2000, phaseFlags 2), 46805 and 112154
////   (state 6, targetFlags 2, flags 2, until removed), 7022 (Spell4 4178, state 6,
////   targetFlags 1), 114394 (state 6, prerequisiteIdTargetPersistence 13428), 191112 (state
////   23, dataBits01 2), 229781 (state 6, prerequisiteIdTargetApply 4106) and 6640 (state 1,
////   targetFlags 2, durationTime 1000, flags 512). The fixture holds one client row of the
////   type, 60879 (Spell4 32339, targetFlags 1, flags 514, state 1, dataBits01 30), so the
////   others are planted with their columns.
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the area.
//// - `Spell4Effects.phaseFlags`: bit n is phase n; a row of 0 is selected by no phase.
//// - `Prerequisite` condition types 38 and 28: a type 38 condition reads a unit that is a
////   creature of a row, which the cast rule checks for each struck unit; a type 28 reads a
////   creature's own combat state, which each struck creature checks.

import fixture_tables
import genesis_prime/game/activate.{Planned}
import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{Always}
import genesis_prime/game/spend
import genesis_prime/game/unit_state
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables

/// Telekinetic Strike's Spell4, whose tree the planted rows hold (`spell_tables`).
const strike = 32_893

/// A type 15 row of a planted spell aimed by `target_flags`, in every phase, of state 6 for
/// 8500 ms, with these columns instead of its own.
fn state_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(15)),
    #("targetFlags", Integer(target_flags)),
    #("dataBits00", Integer(6)),
    #("durationTime", Integer(8500)),
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

fn unit_states_of(rows rows: spell_tables.Rows) -> List(spell_plan.UnitState) {
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
  spell_plan.payloads(spell:, as_kind: spell_plan.as_unit_state)
}

/// What the plan makes of a row of the type in memory, in a place that hits no foes: every
/// column 0 but those given.
fn reading_of(
  target_flags target_flags: Int,
  change change: fn(spell4_effects.Spell4Effects) ->
    spell4_effects.Spell4Effects,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  spell_tables.read_row(
    effect: change(spell_tables.blank_effect(
      id: 99_097,
      spell: 1,
      effect_type: 15,
      target_flags:,
    )),
    place: spell_tables.pressed,
  )
}

pub fn a_timed_unit_state_row_aimed_at_the_target_is_a_planned_unit_state_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of Spell4Effects 64365 (state 6, targetFlags 2, durationTime 8500, phaseFlags
  // 1), planted under an id no client row holds.
  assert unit_states_of(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_097, target_flags: 2, columns: [
          #("phaseFlags", Integer(1)),
        ]),
      ),
    )
    == [
      spell_plan.UnitState(
        effect_id: Spell4EffectsId(99_097),
        phase_flags: 1,
        aim: spell_plan.AimsAtPrimaryTarget,
        row: unit_state.Row(state: 6, delay_ms: 0, duration_ms: 8500),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the row's state, delay, duration, aim and phases are read; emmComparison 0 and emmValue 0 are the tag"
  assert effect_kind.is_read(effect_type: 15)
    && effect_kind.is_row_read(effect_type: 15, target_flags: 2)
    as "type 15 is read for a row aimed past the caster"
  assert effect_kind.kind_of(effect_type: 15) == effect_kind.UnitState
}

pub fn an_area_aimed_unit_state_row_keeps_its_delay_and_phase_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of Spell4Effects 204411: targetFlags 4, state 6, delayTime 500, durationTime
  // 2000, phaseFlags 2.
  assert unit_states_of(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_098, target_flags: 4, columns: [
          #("delayTime", Integer(500)),
          #("durationTime", Integer(2000)),
          #("phaseFlags", Integer(2)),
        ]),
      ),
    )
    == [
      spell_plan.UnitState(
        effect_id: Spell4EffectsId(99_098),
        phase_flags: 2,
        aim: spell_plan.AimsAtArea,
        row: unit_state.Row(state: 6, delay_ms: 500, duration_ms: 2000),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the delay of 500 and the second phase are kept"
}

pub fn a_unit_state_row_aimed_at_the_caster_alone_is_left_out_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 4178's row 7022 is aimed at the caster alone (targetFlags 1); a player's own
  // state needs a creature's strike to read it, which no rule does yet.
  assert reading_of(target_flags: 1, change: fn(row) {
      spell4_effects.Spell4Effects(..row, data_bits00: 6)
    })
    == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateAimedAtTheCasterOnly))
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_099, target_flags: 1, columns: []),
      ),
    )
    as "and the spell still plans"
  assert !list.contains(spell_tables.listed_effect_ids(spell:), 99_099)
    as "without the row among its effects"
}

pub fn an_until_removed_unit_state_row_past_the_caster_is_left_out_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 46805 and 112154 (state 6, targetFlags 2) hold flags 2, bit 2 of
  // `Spell4Effects.flags`: the state lasts until removed, which no rule ends on a creature.
  assert reading_of(target_flags: 2, change: fn(row) {
      spell4_effects.Spell4Effects(..row, data_bits00: 6, flags: 2)
    })
    == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateUntilRemoved))
  assert reading_of(target_flags: 4, change: fn(row) {
      spell4_effects.Spell4Effects(..row, data_bits00: 6, flags: 514)
    })
    == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateUntilRemoved))
    as "bit 2 among others (514) is the same"
  let assert Ok(spell_plan.Applied(..)) =
    reading_of(target_flags: 2, change: fn(row) {
      spell4_effects.Spell4Effects(
        ..row,
        data_bits00: 1,
        flags: 512,
        duration_time: 1000,
      )
    })
    as "flags 512 (Spell4Effects 6640) is not bit 2: that row is timed"
  Nil
}

pub fn a_unit_state_row_behind_persistence_is_left_out_and_its_spell_still_plans_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 114394 (state 6, targetFlags 2) holds prerequisiteIdTargetPersistence
  // 13428: it keeps its state through a death or a leave, which no creature rule holds.
  assert reading_of(target_flags: 2, change: fn(row) {
      spell4_effects.Spell4Effects(
        ..row,
        data_bits00: 6,
        duration_time: 15_000,
        prerequisite_id_target_persistence: 13_428,
      )
    })
    == Ok(spell_plan.LeftOut(why: spell_plan.UnitStateBehindPersistence))
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_100, target_flags: 2, columns: [
          #("prerequisiteIdTargetPersistence", Integer(13_428)),
        ]),
      ),
    )
    as "the spell still plans"
  assert spell_plan.payloads(spell:, as_kind: spell_plan.as_unit_state) == []
}

pub fn a_unit_state_row_with_unread_data_is_left_out_naming_the_column_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 191112 (state 23, targetFlags 2) holds dataBits01 2; no client code reads
  // a row of the type (`Spell4Effects.effectType.15`), so what the column means is unknown.
  assert reading_of(target_flags: 2, change: fn(row) {
      spell4_effects.Spell4Effects(
        ..row,
        data_bits00: 23,
        data_bits01: 2,
        duration_time: 20_000,
      )
    })
    == Ok(
      spell_plan.LeftOut(why: spell_plan.UnitStateDataNotRead(
        column: "dataBits01",
      )),
    )
  assert reading_of(target_flags: 2, change: fn(row) {
      spell4_effects.Spell4Effects(
        ..row,
        data_bits00: 6,
        duration_time: 5000,
        data_bits09: 3,
      )
    })
    == Ok(
      spell_plan.LeftOut(why: spell_plan.UnitStateDataNotRead(
        column: "dataBits09",
      )),
    )
    as "each of dataBits01 to dataBits09 is named"
  assert unit_states_of(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_101, target_flags: 2, columns: [
          #("dataBits04", Integer(1)),
        ]),
      ),
    )
    == []
    as "a spell with such a row still plans, without it"
}

pub fn a_unit_state_row_with_no_phase_is_held_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  // phaseFlags 0 is selected by no phase (`Spell4Effects.phaseFlags`; no client row of the
  // type has it, so the row is planted).
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_102, target_flags: 2, columns: [
          #("phaseFlags", Integer(0)),
        ]),
      ),
    )
  assert list.contains(spell_tables.listed_effect_ids(spell:), 99_102)
    as "the row is in the spell's list"
  list.each([0, 1, 2, 3], fn(phase) {
    assert spell_plan.in_phase(
        spell:,
        phase:,
        spent: None,
        as_kind: spell_plan.as_unit_state,
      )
      == []
      as "and no go applies it"
  })
}

/// The rows of a planted unit state aimed by `target_flags`, behind the target apply
/// prerequisite 99_907 of one condition of `condition_type`.
fn gated_rows(
  condition_type condition_type: Int,
  target_flags target_flags: Int,
) -> spell_tables.Rows {
  let rows =
    spell_tables.rows_with_effect(
      effect: state_row(id: 99_103, target_flags:, columns: [
        #("prerequisiteIdTargetApply", Integer(99_907)),
      ]),
    )
  spell_tables.Rows(
    ..rows,
    prerequisites: spell_tables.sorted_by_id([
      spell_tables.prerequisite_row(id: 99_907, flags: 0, conditions: [
        #(condition_type, 1, 0, 48_404),
      ]),
      ..rows.prerequisites
    ]),
  )
}

pub fn a_gated_unit_state_row_yields_a_struck_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of Spell4Effects 229781 (state 6, prerequisiteIdTargetApply 4106), with a
  // planted Prerequisite 99907 of one type 28 condition (in combat, comparison 1), which a
  // struck creature checks against its own state (`prerequisite.checked_by_creature`). A row
  // aimed at the area alone reaches struck units only, so each creature checks the gate.
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: gated_rows(
      condition_type: 28,
      target_flags: 4,
    ))
  let assert [row] =
    spell_plan.payloads(spell:, as_kind: spell_plan.as_unit_state)
  assert row.condition == Always
    as "the unit state holds no gate of its own: the creature checks it"
  let assert [gate] = spell.struck_gates
  assert gate.effect_id == Spell4EffectsId(99_103)
    as "the strike tells the creature the gate"
  assert prerequisite.id(prerequisite: gate.prerequisite)
    == PrerequisiteId(99_907)
  // Aimed at the primary target of a pressed spell the press has no creature to check it:
  // the cast rule checks the gate for each unit the row lands on (type 38).
  let assert Ok(on_target) =
    spell_tables.planned_strike(rows: gated_rows(
      condition_type: 38,
      target_flags: 2,
    ))
  let assert [row] =
    spell_plan.payloads(spell: on_target, as_kind: spell_plan.as_unit_state)
  let assert spell_plan.GatedOnTarget(prerequisite: gate) = row.condition
  assert prerequisite.id(prerequisite: gate) == PrerequisiteId(99_907)
}

pub fn a_unit_state_behind_an_unread_prerequisite_refuses_its_spell_naming_the_issue_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 681 is of type 12 (`Prerequisite.prerequisiteTypeId.12`), which the server
  // has not decoded; planted here as a one-condition prerequisite. A refused row fails its
  // spell's load, as it does for every read type.
  assert !prerequisite.is_read(type_id: 12)
  let assert Error(error) =
    spell_tables.planned_strike(rows: gated_rows(
      condition_type: 12,
      target_flags: 2,
    ))
    as "a unit state behind an undecoded target prerequisite is refused at load"
  assert error
    == spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: strike,
      effect_id: 99_103,
      prerequisite_type: 12,
    )
  let text = spell_plan.describe(error:)
  assert string.contains(text, "12") && string.contains(text, "#818")
    as "the refusal names the type and the issue that will read it"
}

pub fn a_state_1_row_is_planned_and_held_with_no_reading_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 6640: state 1 (Block), targetFlags 2, durationTime 1000, flags 512.
  assert unit_states_of(
      rows: spell_tables.rows_with_effect(
        effect: state_row(id: 99_104, target_flags: 2, columns: [
          #("dataBits00", Integer(1)),
          #("durationTime", Integer(1000)),
          #("flags", Integer(512)),
        ]),
      ),
    )
    == [
      spell_plan.UnitState(
        effect_id: Spell4EffectsId(99_104),
        phase_flags: -1,
        aim: spell_plan.AimsAtPrimaryTarget,
        row: unit_state.Row(state: 1, delay_ms: 0, duration_ms: 1000),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "state 1 is planned like any other"
  assert unit_state.reading_of(state: 1) == unit_state.NoReading
    as "and holds no reading"
}

pub fn a_state_only_spell_makes_the_phase_select_the_target_and_the_area_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 64365 (targetFlags 2) is the only effect of its spell: no damage row asks
  // for the unit, so the type itself makes the phase strike it. The row is planted in a
  // spell of the plan's tables.
  let on_target = spell_tables.unit_state_only_area(target_flags: 2)
  assert list.map(
      spell_plan.in_phase(
        spell: on_target.spell,
        phase: 0,
        spent: None,
        as_kind: spell_plan.as_unit_state,
      ),
      fn(row) { row.effect_id.value },
    )
    == [99_097]
    as "the planted row is the spell's one unit state"
  let assert Ok(phase) =
    spell_area.phase(spell: on_target, phase: 0, spent: None)
  assert phase.strikes_primary_target
    as "targetFlags 2 aims at the cast's target, so the phase strikes the primary target"
  assert !phase.selects_area as "targetFlags 2 does not aim at the area"
  assert phase.damage == [] && phase.controls == []
    as "no damage and no crowd control: only the unit state asks for the unit"
  // Spell4Effects 204411 is aimed at the area (targetFlags 4).
  let assert Ok(on_area) =
    spell_area.phase(
      spell: spell_tables.unit_state_only_area(target_flags: 4),
      phase: 0,
      spent: None,
    )
  assert on_area.selects_area
    as "targetFlags 4 aims at the area, so the phase selects it"
  assert !on_area.strikes_primary_target
}

pub fn an_activated_spell_with_a_unit_state_row_still_activates_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 2821 is the Activate row of Spell4 1817 (targetFlags 2, delay 0,
  // `Spell4Effects.effectType.7`). A UnitStateSet row aimed at the target is added beside
  // it. The activate cast strikes no unit, so it drops the row, as it drops a despawn,
  // and refuses nothing (result 285): the activation works as it does without the row. No
  // client row of the type sits in an activated spell (`coverage_plan_test`).
  fixture_tables.added(
    table: "Spell4Effects",
    copy_of: 2821,
    id: 99_097,
    with: [#("effectType", Integer(15)), #("dataBits00", Integer(6))],
    body: fn(tables) {
      let activations = activate.activations(tables:)
      let assert Ok(Planned(effects:, dropped:, ..)) =
        activate.planned_of(activations:, spell4_id: 1817)
        as "Spell4 1817 is still planned"
      assert list.map(effects, fn(effect) { effect.effect_id.value }) == [2821]
        as "its Activate row stays, so it still activates"
      assert list.map(dropped.unit_states, fn(effect_id) { effect_id.value })
        == [99_097]
        as "the unit state row is the one the activate cast drops"
      assert dropped.signals == [] && dropped.despawns == []
    },
  )
}
