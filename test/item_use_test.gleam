//// What the client lets a player do with an item before it sends 0x943
//// (`genesis_prime/game/item_use`). Expected values come from these places.
//// - UseItem `0x1403998e0` and StartItemUseCast `0x140398cc0`: the item's spell is
////   ItemSpecial.spell4IdOnActivate of Item2.itemSpecialId00; the checks run in the
////   order level (26), second place (always {300, 0xffffffff} unless the spell's
////   targetType is 6), then the quest checks when Item2.quest2IdActivationRequired is
////   set: a whole quest (objective -1) gives 29 in state 2 or 3 and 28 unless the
////   state is 1; a named objective gives 29 when done and 28 when not open; a
////   checklist objective tested at a unit that is not the player gives 28 when the
////   unit's checklist index is -1 or its bit is counted (`0x140551730`).
//// - `ItemSpecial.prerequisiteIdGeneric00`: only the equip check reads it; use does not.
////
//// The client's rows in the fixture:
//// - Item2 12444 -> ItemSpecial 4363 -> Spell4 26663 (Spell4Base 13157, target
////   mechanic 5, targetType 1); quest2IdActivationRequired 4743, objective -1.
//// - Item2 12402 -> ItemSpecial 4350 -> Spell4 1545; names no quest.
//// - Item2 21966 -> ItemSpecial 5410 -> Spell4 41914 (target mechanic 1, targetType 0);
////   quest 7833, objective index 1, which is QuestObjective 14327 (type 14, a
////   checklist of TargetGroup 4902, count 3).

import character_tables
import fixture_tables
import genesis_prime/game/item_use.{Declined, NotSentByClient}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/message/cast_result.{
  ItemObjectiveComplete, ItemQuestRequirementsNotMet, ItemTooHighLevel,
}
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/table/id.{Item2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}
import quest_support

const grenade = 12_444

const generic_item = 12_402

const objective_item = 21_966

const grenade_quest = 4743

const security_quest = 7833

/// The second place the client always sends unless the spell is an item on item
/// (`local_138 = 0xffffffff0000012c` in StartItemUseCast).
fn no_second_item() -> ItemPlace {
  ItemPlace(location: 300, bag_index: 0xffffffff)
}

fn grenade_quest_accepted() -> QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id: grenade_quest, progress: [0, 0, 0, 0]),
  ])
}

/// The log of quest 7833 accepted with these progress values for its two objectives
/// and this mask of done objectives. Its objective 1 (QuestObjective 14327, flags 3) is
/// reachable once objective 0 (QuestObjective 14647, flags 0) is done (`0x140553790`).
fn security_log(
  done_mask done_mask: Int,
  progress progress: List(Int),
) -> QuestLog {
  quest_support.log_of(rows: [
    quest_support.active(
      quest_id: security_quest,
      state: 1,
      placeholder: 0,
      tracked: False,
      done_mask:,
      progress:,
    ),
  ])
}

fn used(
  tables tables: table_store.Tables,
  item item: Int,
  level level: Int,
  quests quests: QuestLog,
  target target: option.Option(Int),
) -> Result(id.Spell4Id, item_use.Refusal) {
  item_use.check(
    tables:,
    item: Item2Id(item),
    player_level: level,
    quests:,
    second_item: no_second_item(),
    target_checklist_index: target,
  )
}

pub fn an_item_casts_the_spell_its_item_special_names_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  assert used(
      tables:,
      item: grenade,
      level: 20,
      quests: grenade_quest_accepted(),
      target: Some(0),
    )
    == Ok(Spell4Id(26_663))
    as "item 12444 casts ItemSpecial 4363's spell"
  assert used(
      tables:,
      item: generic_item,
      level: 20,
      quests: quest_support.log_of(rows: []),
      target: Some(0),
    )
    == Ok(Spell4Id(1545))
    as "item 12402 casts ItemSpecial 4350's spell"
}

pub fn the_grenade_is_used_while_its_quest_is_accepted_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      tables: character_tables.shared(),
      item: grenade,
      level: 20,
      quests: grenade_quest_accepted(),
      target: Some(0),
    )
    == Ok(Spell4Id(26_663))
    as "quest 4743 is in state 1, which the item's whole-quest check takes"
}

pub fn the_grenade_is_refused_29_once_its_quest_is_achieved_or_completed_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  let achieved =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: grenade_quest,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1111,
        progress: [7, 1, 1, 1],
      ),
    ])
  assert quest_log.state(
      log: achieved,
      quest: quest_of(tables:, id: grenade_quest),
    )
    == 2
    as "the log holds the quest in state 2"
  assert used(
      tables:,
      item: grenade,
      level: 20,
      quests: achieved,
      target: Some(0),
    )
    == Error(Declined(
      spell4_id: Spell4Id(26_663),
      result: ItemObjectiveComplete,
    ))
    as "state 2 gives 29"
  let completed =
    quest_support.log_of(rows: [
      quest_support.completed(quest_id: grenade_quest, at: 1000),
    ])
  assert used(
      tables:,
      item: grenade,
      level: 20,
      quests: completed,
      target: Some(0),
    )
    == Error(Declined(
      spell4_id: Spell4Id(26_663),
      result: ItemObjectiveComplete,
    ))
    as "state 3 gives 29"
}

fn quest_of(tables tables: table_store.Tables, id id: Int) -> quest_log.Quest {
  let assert Ok(quest) = quest_log.quest_of(tables:, id:)
    as "the fixture holds the quest"
  quest
}

pub fn the_grenade_is_refused_28_when_its_quest_is_not_active_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      tables: character_tables.shared(),
      item: grenade,
      level: 20,
      quests: quest_support.log_of(rows: []),
      target: Some(0),
    )
    == Error(Declined(
      spell4_id: Spell4Id(26_663),
      result: ItemQuestRequirementsNotMet,
    ))
    as "a quest not in the log is in no state 1"
}

pub fn an_objective_item_is_refused_29_when_its_objective_is_done_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      tables: character_tables.shared(),
      item: objective_item,
      level: 50,
      quests: security_log(done_mask: 0b10, progress: [0, 0b111]),
      target: None,
    )
    == Error(Declined(
      spell4_id: Spell4Id(41_914),
      result: ItemObjectiveComplete,
    ))
    as "objective index 1 of quest 7833 is done"
}

pub fn an_objective_item_is_refused_28_when_its_objective_is_not_open_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      tables: character_tables.shared(),
      item: objective_item,
      level: 50,
      quests: quest_support.log_of(rows: []),
      target: None,
    )
    == Error(Declined(
      spell4_id: Spell4Id(41_914),
      result: ItemQuestRequirementsNotMet,
    ))
    as "an objective of a quest not in the log is not open"
}

pub fn an_objective_item_with_a_self_spell_tests_no_unit_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      tables: character_tables.shared(),
      item: objective_item,
      level: 50,
      quests: security_log(done_mask: 0b1, progress: [1, 0]),
      target: Some(-1),
    )
    == Ok(Spell4Id(41_914))
    as "spell 41914 is targetType 0: the unit is the player and is not tested"
}

pub fn an_item_that_names_no_quest_makes_no_quest_check_test() -> Nil {
  use <- owned_test.run(10_000)
  assert used(
      tables: character_tables.shared(),
      item: generic_item,
      level: 19,
      quests: quest_support.log_of(rows: []),
      target: Some(-1),
    )
    == Ok(Spell4Id(1545))
    as "Item2 12402 names no quest, and its ItemSpecial's prerequisite does not gate use"
}

pub fn an_objective_item_is_refused_28_at_a_target_with_no_checklist_index_test() -> Nil {
  use <- owned_test.run(10_000)
  // Item 21966 given the grenade's ItemSpecial, so its spell is the type 1 spell 26663.
  use tables <- fixture_tables.changed(
    table: "Item2",
    id: objective_item,
    with: [#("itemSpecialId00", Integer(4363))],
  )
  let log = security_log(done_mask: 0b1, progress: [1, 0])
  assert used(
      tables:,
      item: objective_item,
      level: 50,
      quests: log,
      target: Some(-1),
    )
    == Error(Declined(
      spell4_id: Spell4Id(26_663),
      result: ItemQuestRequirementsNotMet,
    ))
    as "a target of checklist index -1 is in no checklist"
  assert used(
      tables:,
      item: objective_item,
      level: 50,
      quests: log,
      target: Some(2),
    )
    == Ok(Spell4Id(26_663))
    as "a target of index 2 whose bit is clear is taken"
}

pub fn an_objective_item_is_refused_28_at_a_target_already_counted_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- fixture_tables.changed(
    table: "Item2",
    id: objective_item,
    with: [#("itemSpecialId00", Integer(4363))],
  )
  assert used(
      tables:,
      item: objective_item,
      level: 50,
      quests: security_log(done_mask: 0b1, progress: [1, 0b100]),
      target: Some(2),
    )
    == Error(Declined(
      spell4_id: Spell4Id(26_663),
      result: ItemQuestRequirementsNotMet,
    ))
    as "bit 2 of objective 14327's mask is counted"
}

pub fn an_item_above_the_players_level_is_refused_26_test() -> Nil {
  use <- owned_test.run(10_000)
  use tables <- fixture_tables.changed(table: "Item2", id: grenade, with: [
    #("requiredLevel", Integer(10)),
  ])
  assert used(
      tables:,
      item: grenade,
      level: 9,
      quests: grenade_quest_accepted(),
      target: Some(0),
    )
    == Error(Declined(spell4_id: Spell4Id(26_663), result: ItemTooHighLevel))
    as "level 9 is below the item's level 10"
  assert used(
      tables:,
      item: grenade,
      level: 10,
      quests: grenade_quest_accepted(),
      target: Some(0),
    )
    == Ok(Spell4Id(26_663))
    as "level 10 meets it"
}

pub fn a_second_item_place_is_sent_only_for_an_item_on_item_spell_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = character_tables.shared()
  let check = fn(second_item) {
    item_use.check(
      tables:,
      item: Item2Id(grenade),
      player_level: 20,
      quests: grenade_quest_accepted(),
      second_item:,
      target_checklist_index: Some(0),
    )
  }
  assert check(no_second_item()) == Ok(Spell4Id(26_663))
    as "the client's own second place is taken"
  assert check(ItemPlace(location: 1, bag_index: 2)) == Error(NotSentByClient)
    as "spell 26663 is targetType 1, so the client never sends a second item"
}
