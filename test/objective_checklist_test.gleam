//// What an activation of a unit does to a checklist objective (`genesis_prime/game/objective`,
//// types 14 and 28; the talk to a type 18 target is in `interaction_talk_target_test`).
//// Expected values come from these places.
//// - `0x140611680` and `opcode.0x361`: the objective's stored progress is a 32-bit mask
////   with one bit for each unit counted (the unit's checklist index), the client's
////   shown progress is the number of bits set (`0x1406113b0`) and the objective is done
////   once that reaches its count (`0x1406115a0`); the server sends the whole mask.
//// - `QuestObjective.type.14`, `.28`: the data of a type 14 objective is a TargetGroup, and
////   the data of a type 28 one a PathSoldierActivate row whose `creature2Id` is the
////   unit; the objective is a checklist when that row's mode is 1 or 2.
////
//// The client's rows in the fixture:
//// - quest 10520: objective 0 is 21294 (type 14, TargetGroup 14425, count 3); 14425 is
////   a type 1 group of Creature2 73500. Creature 73464 is in no group of a checklist.
//// - quest 5261: objective 7647 (type 28, PathSoldierActivate 37, count 4); row 37 is
////   mode 1 and names Creature2 35249.

import character_tables
import genesis_prime/game/objective.{Advanced, SendProgress, Used}
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/store.{ActiveQuest, QuestRow}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{Some}
import owned_test
import quest_support

const checklist_quest = 10_520

const checklist_creature = 73_500

const path_quest = 5261

const path_creature = 35_249

const outsider = 73_464

/// The unit of a creature as the client's group test reads it: its Creature2 id, the
/// Faction2 its 0x262 gave it (these tests give 0) and its row's UnitRace.
fn unit_of(
  tables tables: table_store.Tables,
  creature creature: Int,
) -> target_group.Unit {
  let assert Ok(row) = creature2.get(tables, Creature2Id(creature))
    as "the fixture holds the creature's row"
  target_group.Unit(
    creature_id: Creature2Id(creature),
    faction_id: Faction2Id(0),
    unit_race_id: creature2.unit_race_id(row),
  )
}

fn used(
  tables tables: table_store.Tables,
  creature creature: Int,
  index index: Int,
) -> objective.Event {
  Used(target: unit_of(tables:, creature:), checklist_index: index)
}

/// The log of quest 10520 accepted with nothing counted.
fn fresh_log() -> quest_log.QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id: checklist_quest, progress: [0, 0, 0, 0, 0]),
  ])
}

/// The stored progress of the quest's objectives, as the log is saved.
fn stored(log log: quest_log.QuestLog, quest_id quest_id: Int) -> List(Int) {
  let assert [QuestRow(active: Some(ActiveQuest(progress:, ..)), ..)] =
    quest_log.rows(log:, now_ms: 0)
    |> list.filter(fn(row) { row.quest_id == quest_id })
    as "the quest is in the active list"
  progress
}

/// The progress the client shows for the quest's objective 0 (`0x1406113b0`).
fn shown(
  log log: quest_log.QuestLog,
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> Int {
  let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
    as "the fixture holds the quest"
  quest_log.objective_progress(log:, quest:, index: 0)
}

pub fn activating_a_checklist_target_sets_its_bit_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let counted =
    objective.advance(
      log: fresh_log(),
      tables:,
      event: used(tables:, creature: checklist_creature, index: 2),
      now_ms: 0,
    )
  assert counted.effects
    == [
      SendProgress(quest_id: checklist_quest, objective_index: 0, progress: 4),
    ]
    as "the unit of index 2 sets bit 2, and 0x361 carries the whole mask (opcode.0x361)"
  assert stored(log: counted.log, quest_id: checklist_quest) == [4, 0, 0, 0, 0]
    as "the stored progress of objective 0 is the mask"
  assert shown(log: counted.log, tables:, quest_id: checklist_quest) == 1
    as "the client shows the one bit set (0x1406113b0)"
}

pub fn a_checklist_is_done_when_its_bit_count_reaches_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let assert Ok(quest) = quest_log.quest_of(tables:, id: checklist_quest)
    as "the fixture holds the quest"
  let count = fn(log, index) {
    objective.advance(
      log:,
      tables:,
      event: used(tables:, creature: checklist_creature, index:),
      now_ms: 0,
    ).log
  }

  let two = list.fold([0, 1], fresh_log(), count)
  assert !quest_log.objective_done(log: two, quest:, index: 0)
    as "two bits of a count of 3 leave the objective open"
  assert shown(log: two, tables:, quest_id: checklist_quest) == 2

  let three = count(two, 2)
  assert quest_log.objective_done(log: three, quest:, index: 0)
    as "the third bit reaches the count"
  assert shown(log: three, tables:, quest_id: checklist_quest) == 3
  assert stored(log: three, quest_id: checklist_quest) == [7, 0, 0, 0, 0]

  let apart = list.fold([31, 0, 17], fresh_log(), count)
  assert quest_log.objective_done(log: apart, quest:, index: 0)
    as "any three bits do, bit 31 among them"
  assert stored(log: apart, quest_id: checklist_quest)
    == [0x80020001, 0, 0, 0, 0]
    as "bit 31 is part of the mask"
}

pub fn a_target_already_counted_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let event = used(tables:, creature: checklist_creature, index: 2)
  let first = objective.advance(log: fresh_log(), tables:, event:, now_ms: 0)
  let again = objective.advance(log: first.log, tables:, event:, now_ms: 0)
  assert again == Advanced(log: first.log, effects: [])
    as "the bit is set already: no second 0x361 and the log is as it was"
  assert stored(log: again.log, quest_id: checklist_quest) == [4, 0, 0, 0, 0]
    as "one bit, not two"
}

pub fn activating_a_path_soldier_target_sets_its_bit_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: path_quest, progress: [0]),
    ])
  let counted =
    objective.advance(
      log:,
      tables:,
      event: used(tables:, creature: path_creature, index: 1),
      now_ms: 0,
    )
  assert counted.effects
    == [SendProgress(quest_id: path_quest, objective_index: 0, progress: 2)]
    as "the unit PathSoldierActivate 37 names sets its bit in a mode 1 objective"
  assert shown(log: counted.log, tables:, quest_id: path_quest) == 1
    as "one bit of a count of 4"
}

pub fn a_unit_outside_the_target_group_changes_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let log = fresh_log()
  assert objective.advance(
      log:,
      tables:,
      event: used(tables:, creature: outsider, index: 1),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "a unit TargetGroup 14425 does not hold takes no bit"
  assert objective.advance(
      log:,
      tables:,
      event: used(tables:, creature: checklist_creature, index: 32),
      now_ms: 0,
    )
    == Advanced(log:, effects: [])
    as "an index of 32 or more is never counted (0x140611680)"
}
