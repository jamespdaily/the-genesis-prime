//// The QuestAdvanceObjective rows of the plan (`genesis_prime/game/spell_plan` `QuestAdvance`,
//// `genesis_prime/game/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.42`: dataBits00 is a Quest2 id, dataBits01 the objective's
////   index and dataBits02 the amount (`table_rows -- Spell4Effects effectType=42`, 251 rows);
////   the client reads no other column of the type, so a row that holds one is left out by name.
//// - Spell4 24501 (the Experimental Loftite Railgun): 89873 (quest 3769 index 0, amount 1,
////   delayTime 6000, every phase, aimed at the caster 1), 89874 (quest 3785 index 0, amount 1,
////   delayTime 0, caster apply prerequisite 14533) and 89875 (a DespawnUnit, type 97, aimed at
////   the primary target 2), 89883 (type 71, which no rule reads).
//// - Spell4 45904 (Ignite Tower 2): 107313 (quest 8262 index 2, amount 2, delayTime 1500,
////   every phase).
//// - `Spell4Effects.targetFlags` (a guess, the client has no reader of the column): bit 1 the
////   caster, 2 the primary target, 4 the area; a value of 0 and the values with bit 8 and not
////   bit 1 have no aim.
//// - `Spell4Effects.phaseFlags`: bit n is phase n.

import cast_support
import genesis_prime/game/effect_kind
import genesis_prime/game/spell_plan.{
  AimsAtCaster, AimsAtPrimaryTarget, Always, Applied, GatedOnCaster, LeftOut,
  QuestAdvance, QuestAdvanceEffect,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None}
import owned_test
import spell_tables

/// The effect row of this type 42 shape, aimed by `target_flags`, with these phases, delay and
/// quest columns and every other column 0.
fn row(
  target_flags target_flags: Int,
  phase_flags phase_flags: Int,
) -> spell4_effects.Spell4Effects {
  spell4_effects.Spell4Effects(
    ..spell_tables.blank_effect(
      id: 99_042,
      spell: 1,
      effect_type: 42,
      target_flags:,
    ),
    phase_flags:,
    data_bits00: 3769,
    data_bits01: 2,
    data_bits02: 3,
    delay_time: 1500,
  )
}

fn read(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  spell_tables.read_row(effect:, place: spell_tables.pressed)
}

pub fn a_type_42_row_plans_its_quest_index_amount_delay_and_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  let railgun = spell_tables.client_spell(spell4_id: 24_501)
  let assert [first, second] =
    spell_plan.payloads(spell: railgun, as_kind: spell_plan.as_quest_advance)
    as "Spell4 24501 holds two type 42 rows, 89873 and 89874"
  assert first
    == QuestAdvance(
      effect_id: Spell4EffectsId(89_873),
      phase_flags: -1,
      aim: AimsAtCaster,
      condition: Always,
      tag: spend.EqualTo(value: 0),
      quest_id: 3769,
      objective_index: 0,
      amount: 1,
      delay_ms: 6000,
    )
    as "89873: quest 3769 index 0 amount 1, delayTime 6000, every phase, aimed at the caster, no gate"
  assert second.effect_id == Spell4EffectsId(89_874)
    && second.quest_id == 3785
    && second.objective_index == 0
    && second.amount == 1
    && second.delay_ms == 0
    && second.aim == AimsAtCaster
    as "89874: quest 3785 index 0 amount 1, no delay"
  let assert GatedOnCaster(gates: [_]) = second.condition
    as "89874 sits behind the one caster apply prerequisite 14533"
  assert list.map(
      spell_plan.payloads(spell: railgun, as_kind: spell_plan.as_despawn),
      fn(despawn) { despawn.effect_id.value },
    )
    == [89_875]
    as "the spell's DespawnUnit row 89875 keeps its kind"
  assert list.length(railgun.effects) == 3
    as "the plan holds the two advances and the despawn: the type 71 row 89883 is read by no rule"
  let tower = spell_tables.client_spell(spell4_id: 45_904)
  assert list.map(
      spell_plan.payloads(spell: tower, as_kind: spell_plan.as_quest_advance),
      fn(advance) {
        #(
          advance.effect_id.value,
          advance.quest_id,
          advance.objective_index,
          advance.amount,
          advance.delay_ms,
        )
      },
    )
    == [#(107_313, 8262, 2, 2, 1500)]
    as "107313: quest 8262 index 2 amount 2 after 1500 ms"
  // No client row of the fixture names a single go in a type 42 row, so the row is made.
  let assert Ok(Applied(spell_plan.ReadEffects(effects: [planned]))) =
    read(effect: row(target_flags: 1, phase_flags: -65_534))
    as "a row of phaseFlags 0xffff0002 is planned"
  assert planned.phase_flags == -65_534
    as "bit 1 of the flags names go 1, as the plan reads the column for every kind"
  let phased =
    cast_support.with_effects(
      spell: cast_support.child(spell4_id: 1, base: 1),
      kinds: [planned.kind],
    )
  assert spell_plan.in_phase(
      spell: phased,
      phase: 1,
      spent: None,
      as_kind: spell_plan.as_quest_advance,
    )
    != []
    as "the row applies at go 1"
  assert spell_plan.in_phase(
      spell: phased,
      phase: 0,
      spent: None,
      as_kind: spell_plan.as_quest_advance,
    )
    == []
    as "and not at go 0"
}

type AimCase {
  AimCase(why: String, target_flags: Int, planned: Result(spell_plan.Aim, Nil))
}

pub fn a_type_42_row_is_read_by_its_aim_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      AimCase("the caster", 1, Ok(AimsAtCaster)),
      AimCase("the primary target alone", 2, Ok(AimsAtPrimaryTarget)),
      AimCase(
        "the caster and the primary target: read for the caster",
        3,
        Ok(AimsAtCaster),
      ),
      AimCase("the area alone is not read", 4, Error(Nil)),
      AimCase(
        "the caster and the area: read for the caster",
        5,
        Ok(AimsAtCaster),
      ),
      AimCase("the primary target and the area is not read", 6, Error(Nil)),
      AimCase("all three: read for the caster", 7, Ok(AimsAtCaster)),
      AimCase("no aim: the client refuses 0", 0, Error(Nil)),
      AimCase("bit 8 alone has no known aim", 8, Error(Nil)),
      AimCase(
        "bit 8 with the caster is read for the caster",
        9,
        Ok(AimsAtCaster),
      ),
      AimCase("bit 8 with the primary target alone has no aim", 10, Error(Nil)),
    ],
    fn(aim) {
      let reading =
        read(effect: row(target_flags: aim.target_flags, phase_flags: -1))
      case aim.planned {
        Ok(expected) -> {
          let assert Ok(reading) = reading as aim.why
          let assert [QuestAdvanceEffect(quest_advance:)] =
            spell_tables.planned_kinds(reading:)
            as aim.why
          assert quest_advance.aim == expected as aim.why
          Nil
        }
        Error(Nil) -> {
          assert reading == Ok(LeftOut(why: spell_plan.AimedAtOtherUnits))
            as aim.why
          Nil
        }
      }
      assert effect_kind.is_row_read(
          effect_type: 42,
          target_flags: aim.target_flags,
        )
        == result_is_ok(result: aim.planned)
        as aim.why
    },
  )
}

fn result_is_ok(result result: Result(a, Nil)) -> Bool {
  case result {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

type ColumnCase {
  ColumnCase(
    why: String,
    effect: spell4_effects.Spell4Effects,
    left_out: spell_plan.LeftOutReason,
  )
}

pub fn a_type_42_row_with_an_unread_column_is_left_out_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  let base = row(target_flags: 1, phase_flags: -1)
  list.each(
    [
      ColumnCase(
        "dataBits03 (Spell4Effects 166903)",
        spell4_effects.Spell4Effects(..base, data_bits03: 1),
        spell_plan.QuestAdvanceColumnNotRead(column: "dataBits03"),
      ),
      ColumnCase(
        "dataBits04 (Spell4Effects 91090, 76072)",
        spell4_effects.Spell4Effects(..base, data_bits04: 1),
        spell_plan.QuestAdvanceColumnNotRead(column: "dataBits04"),
      ),
      ColumnCase(
        "damageType (Spell4Effects 91090, 196968)",
        spell4_effects.Spell4Effects(..base, damage_type: 3),
        spell_plan.QuestAdvanceColumnNotRead(column: "damageType"),
      ),
      ColumnCase(
        "flags 1 (Spell4Effects 78189 and six others)",
        spell4_effects.Spell4Effects(..base, flags: 1),
        spell_plan.QuestAdvanceColumnNotRead(column: "flags"),
      ),
      ColumnCase(
        "dataBits05 (Spell4Effects 76525 and three others)",
        spell4_effects.Spell4Effects(..base, data_bits05: 15),
        spell_plan.QuestAdvanceColumnNotRead(column: "dataBits05"),
      ),
      ColumnCase(
        "a caster persistence prerequisite (Spell4Effects 50610, 54612)",
        spell4_effects.Spell4Effects(
          ..base,
          prerequisite_id_caster_persistence: 7791,
        ),
        spell_plan.QuestAdvanceColumnNotRead(
          column: "prerequisiteIdCasterPersistence",
        ),
      ),
      ColumnCase(
        "a duration",
        spell4_effects.Spell4Effects(..base, duration_time: 1000),
        spell_plan.QuestAdvanceColumnNotRead(column: "durationTime"),
      ),
      ColumnCase(
        "an amount of 0 adds nothing",
        spell4_effects.Spell4Effects(..base, data_bits02: 0),
        spell_plan.QuestAdvanceAddsNothing,
      ),
      ColumnCase(
        "a negative amount adds nothing",
        spell4_effects.Spell4Effects(..base, data_bits02: -1),
        spell_plan.QuestAdvanceAddsNothing,
      ),
    ],
    fn(column) {
      assert read(effect: column.effect) == Ok(LeftOut(why: column.left_out))
        as column.why
    },
  )
  // A row the quest columns of which name nothing is planned: a pair names no objective.
  let assert Ok(Applied(..)) =
    read(
      effect: spell4_effects.Spell4Effects(
        ..base,
        data_bits00: 1,
        data_bits01: 9,
      ),
    )
    as "a quest or an index the tables lack is planned and names nothing at run time"
  Nil
}
