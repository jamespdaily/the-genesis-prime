//// The despawns of the plan (`genesis_prime/game/spell_plan` `Despawn`,
//// `genesis_prime/game/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.97`: the columns of the client's rows (`table_rows --
////   Spell4Effects effectType=97`): 56028 (Spell4 30600, targetFlags 2, delayTime 4000,
////   phaseFlags 1), 87795 (Spell4 39854, targetFlags 6, delay 60000), 115345 (Spell4 48292,
////   targetFlags 7, delay 2500), 75532's spell 195090 (targetFlags 3), 91427 (Spell4 40913,
////   targetFlags 4, delay 4000) and 99864 (Spell4 43559, targetFlags 2, delay 0); rows with
////   data: 95265 (targetFlags 2, dataBits00 1), 97774 (targetFlags 2, dataBits00 247248),
////   70045 (targetFlags 2, dataBits01 5); a row aimed at the caster alone: 51664
////   (targetFlags 1, dataBits00 1) and 99222 (targetFlags 1, phaseFlags 0).
//// - The fixture holds client rows of the type: 71140 (Spell4 35436, targetFlags 2, delay
////   4000, phaseFlags 1) and 70045 (Spell4 35046, targetFlags 2, dataBits01 5).
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the area.
//// - `Prerequisite` condition types 38 and 12: the server decodes the first and not the
////   second (`prerequisite.is_read`); a type 38 condition reads a creature's own
////   state, which each struck creature checks.

import fixture_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{Always}
import genesis_prime/game/spend
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

/// A type 97 row of a planted spell aimed by `target_flags`, in every phase, with these
/// columns beside its id, spell and type.
fn despawn_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(97)),
    #("targetFlags", Integer(target_flags)),
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

fn despawns_of(rows rows: spell_tables.Rows) -> List(spell_plan.Despawn) {
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
  spell_plan.payloads(spell:, as_kind: spell_plan.as_despawn)
}

/// What the plan makes of a client-shaped row, in a place that hits no foes.
fn reading_of(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  spell_tables.read_row(effect:, place: spell_tables.pressed)
}

pub fn a_despawn_row_aimed_at_the_target_is_a_planned_despawn_with_its_delay_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of Spell4Effects 56028 (delay 4000, phaseFlags 1, targetFlags 2), planted
  // under an id no client row holds.
  assert despawns_of(
      rows: spell_tables.rows_with_effect(
        effect: despawn_row(id: 99_097, target_flags: 2, columns: [
          #("delayTime", Integer(4000)),
          #("phaseFlags", Integer(1)),
        ]),
      ),
    )
    == [
      spell_plan.Despawn(
        effect_id: Spell4EffectsId(99_097),
        phase_flags: 1,
        delay_ms: 4000,
        aim: spell_plan.AimsAtPrimaryTarget,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the row's delay, phases and aim are read; emmComparison 0 and emmValue 0 are the tag"
  assert effect_kind.is_read(effect_type: 97)
    && effect_kind.is_row_read(effect_type: 97, target_flags: 2)
    as "type 97 is read for a row aimed past the caster"
  let assert Ok(row) =
    spell4_effects.get(
      tables: fixture_tables.shared(),
      id: Spell4EffectsId(71_140),
    )
    as "the client's row 71140 is in the fixture"
  let assert Ok(spell_plan.Applied(read)) = reading_of(effect: row)
  assert spell_tables.planned_kinds(reading: spell_plan.Applied(read))
    == [
      spell_plan.DespawnEffect(spell_plan.Despawn(
        effect_id: Spell4EffectsId(71_140),
        phase_flags: 1,
        delay_ms: 4000,
        aim: spell_plan.AimsAtPrimaryTarget,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      )),
    ]
    as "the client's row 71140 (targetFlags 2, delay 4000, phaseFlags 1) is read as its columns say"
}

pub fn a_union_aim_despawn_keeps_only_the_part_past_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // targetFlags 4 is the area (Spell4Effects 91427), 6 the target and the area (87795), 3
  // the caster and the target (the row of 75532's spell 195090) and 7 all three (115345):
  // the caster's bit is not a despawn.
  list.each(
    [
      #(4, spell_plan.AimsAtArea),
      #(6, spell_plan.AimsAtPrimaryTargetAndArea),
      #(3, spell_plan.AimsAtPrimaryTarget),
      #(7, spell_plan.AimsAtPrimaryTargetAndArea),
    ],
    fn(shape) {
      let #(flags, past_the_caster) = shape
      let assert [row] =
        despawns_of(
          rows: spell_tables.rows_with_effect(
            effect: despawn_row(id: 99_098, target_flags: flags, columns: []),
          ),
        )
      assert row.aim == past_the_caster
    },
  )
}

pub fn a_despawn_row_aimed_at_the_caster_alone_is_left_out_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 51664 and 99222 are aimed at the caster alone; the plan reads a creature
  // caster's casts nowhere, and a player is never removed.
  let row =
    spell_tables.blank_effect(
      id: 51_664,
      spell: 1,
      effect_type: 97,
      target_flags: 1,
    )
  assert reading_of(effect: row)
    == Ok(spell_plan.LeftOut(why: spell_plan.DespawnAimedAtTheCasterOnly))
  assert !effect_kind.is_row_read(effect_type: 97, target_flags: 1)
    as "the measure counts such a row unread"
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: despawn_row(id: 99_099, target_flags: 1, columns: []),
      ),
    )
    as "and the spell still plans"
  assert !list.contains(spell_tables.listed_effect_ids(spell:), 99_099)
    as "without the row among its effects"
}

pub fn a_despawn_row_with_unread_data_is_left_out_naming_the_column_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 95265 holds dataBits00 1, 97774 dataBits00 247248 and 70045 dataBits01 5,
  // all aimed at the target; no client code reads either column of this type (the first
  // two are the client's rows' values on a blank row, the last is the client's row).
  let blank =
    spell_tables.blank_effect(
      id: 95_265,
      spell: 1,
      effect_type: 97,
      target_flags: 2,
    )
  assert reading_of(
      effect: spell4_effects.Spell4Effects(..blank, data_bits00: 1),
    )
    == Ok(
      spell_plan.LeftOut(why: spell_plan.DespawnDataNotRead(
        column: "dataBits00",
      )),
    )
  assert reading_of(
      effect: spell4_effects.Spell4Effects(..blank, data_bits00: 247_248),
    )
    == Ok(
      spell_plan.LeftOut(why: spell_plan.DespawnDataNotRead(
        column: "dataBits00",
      )),
    )
  let assert Ok(client_row) =
    spell4_effects.get(
      tables: fixture_tables.shared(),
      id: Spell4EffectsId(70_045),
    )
    as "the client's row 70045 (targetFlags 2, dataBits01 5) is in the fixture"
  assert reading_of(effect: client_row)
    == Ok(
      spell_plan.LeftOut(why: spell_plan.DespawnDataNotRead(
        column: "dataBits01",
      )),
    )
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: despawn_row(id: 99_100, target_flags: 2, columns: [
          #("dataBits00", Integer(1)),
        ]),
      ),
    )
    as "a spell with such a row still plans"
  assert spell_plan.payloads(spell:, as_kind: spell_plan.as_despawn) == []
}

/// The rows of a planted despawn aimed by `target_flags`, behind the target apply
/// prerequisite 99_907 of one condition of `condition_type`.
fn gated_rows(
  condition_type condition_type: Int,
  target_flags target_flags: Int,
) -> spell_tables.Rows {
  let rows =
    spell_tables.rows_with_effect(
      effect: despawn_row(id: 99_101, target_flags:, columns: [
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

pub fn a_gated_despawn_row_yields_a_struck_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // A planted Prerequisite 99907 of one type 28 condition (in combat, comparison 1), which
  // a struck creature checks against its own state
  // (`prerequisite.checked_by_creature`). A row aimed at the area alone reaches struck
  // units only, so each creature checks the gate itself.
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: gated_rows(
      condition_type: 28,
      target_flags: 4,
    ))
  let assert [row] = spell_plan.payloads(spell:, as_kind: spell_plan.as_despawn)
  assert row.condition == Always
    as "the despawn holds no gate of its own: the creature checks it"
  let assert [gate] = spell.struck_gates
  assert gate.effect_id == Spell4EffectsId(99_101)
    as "the strike tells the creature the gate"
  assert prerequisite.id(prerequisite: gate.prerequisite)
    == PrerequisiteId(99_907)
  // Aimed at the primary target of a pressed spell, the press has no creature to check it:
  // the cast rule checks the gate for each unit the row lands on (type 38, the unit is a
  // creature, which no creature checks for itself).
  assert prerequisite.is_read(type_id: 38)
  let assert Ok(on_target) =
    spell_tables.planned_strike(rows: gated_rows(
      condition_type: 38,
      target_flags: 2,
    ))
  let assert [row] =
    spell_plan.payloads(spell: on_target, as_kind: spell_plan.as_despawn)
  let assert spell_plan.GatedOnTarget(prerequisite: gate) = row.condition
  assert prerequisite.id(prerequisite: gate) == PrerequisiteId(99_907)
}

pub fn a_despawn_behind_an_unread_prerequisite_refuses_its_spell_naming_what_it_does_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 681 is of type 12 (`Prerequisite.prerequisiteTypeId.12`), which the server
  // has not decoded; planted here as a one-condition prerequisite.
  assert !prerequisite.is_read(type_id: 12)
  let assert Error(error) =
    spell_tables.planned_strike(rows: gated_rows(
      condition_type: 12,
      target_flags: 2,
    ))
    as "a despawn behind an undecoded target prerequisite is refused at load"
  assert error
    == spell_plan.ApplyPrerequisiteNotRead(
      spell4_id: strike,
      effect_id: 99_101,
      prerequisite_type: 12,
    )
  let text = spell_plan.describe(error:)
  assert string.contains(text, "12")
    && string.ends_with(text, "which is not decoded")
    as "the refusal names the type and says it is not decoded, with no issue"
}

pub fn a_despawn_with_no_phase_is_held_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  // phaseFlags 0 is selected by no phase (`Spell4Effects.phaseFlags`; the two client rows
  // with it, 99222 and 101213, are aimed at the caster, so the row is planted).
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: despawn_row(id: 99_102, target_flags: 2, columns: [
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
        as_kind: spell_plan.as_despawn,
      )
      == []
      as "and no go applies it"
  })
}
