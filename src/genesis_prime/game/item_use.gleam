//// What the client lets a player do with an item before it sends 0x943 (StartItemUseCast
//// `0x140398cc0`, reached from UseItem `0x1403998e0`), as a pure check on the client's
//// tables and the player's quest log.
////
//// ```
//// item ─▶ Item2.itemSpecialId00 ─▶ ItemSpecial.spell4IdOnActivate   no spell: NoItemSpell
////   second place other than {300, 0xffffffff}, spell not type 6    ─▶ NotSentByClient
////   Item2.prerequisiteId (UseItem) fails                           ─▶ 17
////                                      is of a type not read       ─▶ UnreadPrerequisite
////   Item2.maxCharges above 0 (25 in the client)                    ─▶ Charged
////   player level below Item2.requiredLevel                         ─▶ 26
////   Item2.quest2IdActivationRequired set:
////     objective -1 (the quest): state 2 or 3                       ─▶ 29
////                               state other than 1                 ─▶ 28
////     an objective:             done                               ─▶ 29
////                               not open                           ─▶ 28
////                               a checklist and the target unit    ─▶ 28 when its checklist
////                                 (spell targetType 1, 3, 5, 8)       index is -1 or is counted
//// ```
////
//// - **The spell** is ItemSpecial.spell4IdOnActivate of Item2.itemSpecialId00; an item with
////   none never sends 0x943 (the client answers 0x35b or 0x17), so a use of one is not the
////   client's. `ItemSpecial.prerequisiteIdGeneric00` gates only the equip check.
//// - **The second place** is always {300, 0xffffffff} unless the spell is an item on item
////   (targetType 6).
//// - **The unit** the checklist test reads is the player for targetType 0, 2, 6 and 7, which
////   the client does not test, and the player's target for 1, 3, 5 and 8
////   (`0x140551730`).
////
//// - **The order** is the client's (UseItem's prerequisite, then StartItemUseCast's charges,
////   level and quest checks) except that the second place comes first: a body the client
////   never sends ends the connection whatever else would refuse it.
////
//// Gaps, each reported as missing: the item's charges (result 25, StartItemUseCast's first
//// check; the server holds none, so an item with `maxCharges` above 0 is refused as
//// not built; #333), and the objective check of a
//// castMethod 3 quest item, whose unit is read from the quest record's word 0x18 (#334).

import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/shortcut_spell
import genesis_prime/message/cast_result.{
  type CastResult, ItemObjectiveComplete, ItemQuestRequirementsNotMet,
  ItemTooHighLevel, SpellPreRequisites,
}
import genesis_prime/message/item_place.{type ItemPlace, ItemPlace}
import genesis_prime/table/id.{
  type Item2Id, type Spell4Id, ItemSpecialId, Spell4Id,
}
import genesis_prime/table/item2
import genesis_prime/table/item_special
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// Why an item is not cast.
pub type Refusal {
  /// The item has no spell, so the client never sends 0x943 for it: the connection ends.
  NoItemSpell
  /// The second place is not the one the client sends for this spell: the connection ends.
  NotSentByClient
  /// The client refuses the use with this result, naming the item's spell.
  Declined(spell4_id: Spell4Id, result: CastResult)
  /// The item has charges (Item2.maxCharges above 0), which the server does not hold.
  Charged(spell4_id: Spell4Id, max_charges: Int)
  /// The item's prerequisite is of a type the server does not read.
  UnreadPrerequisite(spell4_id: Spell4Id, prerequisite_type: Int)
}

/// The place the client sends as the second item unless the spell is an item on item
/// (`local_138 = 0xffffffff0000012c` in StartItemUseCast).
const no_second_item = ItemPlace(location: 300, bag_index: 0xffffffff)

/// The spell's targetType of an item on item.
const item_on_item = 6

/// The targetTypes whose unit the client tests for a checklist objective: the player's
/// target.
const targeted = [1, 3, 5, 8]

/// The spell the item casts when the client's checks let the player use it. The unit
/// tested for a checklist objective is the checklist index of the player's target, or
/// `None` when the target is no unit that has one (nothing is tested then).
pub fn check(
  tables tables: table_store.Tables,
  item item: Item2Id,
  player_level player_level: Int,
  quests quests: QuestLog,
  second_item second_item: ItemPlace,
  target_checklist_index target_checklist_index: Option(Int),
  prerequisite prerequisite: fn(Int) -> prerequisite.Verdict,
) -> Result(Spell4Id, Refusal) {
  use row <- result.try(
    item2.get(tables:, id: item) |> result.replace_error(NoItemSpell),
  )
  use spell4_id <- result.try(spell_of(tables:, row:))
  use target_type <- result.try(
    spell4.get(tables:, id: spell4_id)
    |> result.replace_error(NoItemSpell)
    |> result.try(fn(spell) {
      shortcut_spell.target_type_of(tables:, row: spell)
      |> result.replace_error(NoItemSpell)
    }),
  )
  let declined = fn(result) { Declined(spell4_id:, result:) }
  use <- bool.guard(
    when: second_item != no_second_item && target_type != item_on_item,
    return: Error(NotSentByClient),
  )
  use Nil <- result.try(case row.prerequisite_id {
    0 -> Ok(Nil)
    prerequisite_id ->
      case prerequisite(prerequisite_id) {
        prerequisite.Passes -> Ok(Nil)
        prerequisite.Fails -> Error(declined(SpellPreRequisites))
        prerequisite.NotRead(prerequisite_type:) ->
          Error(UnreadPrerequisite(spell4_id:, prerequisite_type:))
      }
  })
  use Nil <- result.try(case row.max_charges > 0 {
    True -> Error(Charged(spell4_id:, max_charges: row.max_charges))
    False -> Ok(Nil)
  })
  use Nil <- result.try(case player_level < row.required_level {
    True -> Error(declined(ItemTooHighLevel))
    False -> Ok(Nil)
  })
  quest_check(
    tables:,
    row:,
    quests:,
    unit: case list.contains(targeted, target_type) {
      True -> target_checklist_index
      False -> None
    },
  )
  |> result.map(fn(_) { spell4_id })
  |> result.map_error(declined)
}

/// ItemSpecial.spell4IdOnActivate of the item's ItemSpecial row, when it names one.
fn spell_of(
  tables tables: table_store.Tables,
  row row: item2.Item2,
) -> Result(Spell4Id, Refusal) {
  use special <- result.try(
    item_special.get(tables:, id: ItemSpecialId(row.item_special_id00))
    |> result.replace_error(NoItemSpell),
  )
  case special.spell4_id_on_activate {
    0 -> Error(NoItemSpell)
    spell4_id -> Ok(Spell4Id(spell4_id))
  }
}

/// The quest checks of StartItemUseCast, for an item that names a quest.
fn quest_check(
  tables tables: table_store.Tables,
  row row: item2.Item2,
  quests quests: QuestLog,
  unit unit: Option(Int),
) -> Result(Nil, CastResult) {
  case row.quest2_id_activation_required {
    0 -> Ok(Nil)
    quest_id ->
      case quest_log.quest_of(tables:, id: quest_id) {
        // A quest the client has no row for is in no log.
        Error(_) -> Error(ItemQuestRequirementsNotMet)
        Ok(quest) ->
          case row.quest_objective_activation_required {
            index if index < 0 ->
              case quest_log.state(log: quests, quest:) {
                2 | 3 -> Error(ItemObjectiveComplete)
                1 -> Ok(Nil)
                _ -> Error(ItemQuestRequirementsNotMet)
              }
            index -> objective_check(quests:, quest:, index:, unit:)
          }
      }
  }
}

/// The checks of one objective of the quest: done, open, and for a checklist the unit.
fn objective_check(
  quests quests: QuestLog,
  quest quest: quest_log.Quest,
  index index: Int,
  unit unit: Option(Int),
) -> Result(Nil, CastResult) {
  use <- bool.guard(
    when: quest_log.objective_done(log: quests, quest:, index:),
    return: Error(ItemObjectiveComplete),
  )
  use <- bool.guard(
    when: !quest_log.objective_open(log: quests, quest:, index:),
    return: Error(ItemQuestRequirementsNotMet),
  )
  case is_checklist(quest:, index:), unit {
    True, Some(checklist_index) ->
      case
        checklist_index < 0
        || quest_log.is_marked(
          log: quests,
          quest:,
          index:,
          bit: checklist_index,
        )
      {
        True -> Error(ItemQuestRequirementsNotMet)
        False -> Ok(Nil)
      }
    True, None | False, _ -> Ok(Nil)
  }
}

fn is_checklist(quest quest: quest_log.Quest, index index: Int) -> Bool {
  case list.drop(quest.objectives, index) {
    [objective, ..] -> objective.checklist
    [] -> False
  }
}
