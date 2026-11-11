//// The link from a creature to a quest objective, and whether the player's quest log
//// opens it.
////
//// ```
//// Creature2.questAnimStateId + questAnimObjectiveIndex ──────────┐
//// Creature2.prerequisiteIdAnimState (type 43 conditions, nested) ┴▶ links ─▶ [(quest, index)]
//// the columns + the player's log ─▶ of ─▶ NoLink | OpenLink | ClosedLink | UnreadLink
//// ```
////
//// - **The links** (`Creature2.objective_link`): `questAnimStateId` names a Quest2 and
////   `questAnimObjectiveIndex` the objective's index in it (-1 names the quest alone);
////   `prerequisiteIdAnimState` names a Prerequisite whose type 43 conditions of
////   comparison 1 each name a Quest2 (`objectId`) and an objective index (`value`), in
////   the rows its type 11 conditions of comparison 1 nest too
////   (`Prerequisite.prerequisiteTypeId.11`). The client reads both columns the same way
////   whatever the objective's type, and the server counts a use for the objectives of
////   type 5 and 32 these name (`objective.counts`).
//// - **Whether the link is open** (`SetAnimStatePrerequisiteState`, `0x14046c4d0`): a
////   creature with neither column has no link. A questAnim column is open while its quest
////   is Accepted and, for an index other than -1, the objective is open and the unit's
////   checklist bit is not marked (`QuestAnimInteractKind`, `0x1405a8b30`); when it is
////   closed the check ends there and the prerequisite column is not read. Otherwise a
////   prerequisite column, when set, decides: it is open when the prerequisite passes. A
////   prerequisite the table has no row for fails in the client (`Prerequisite.flags`), so
////   it is closed; the client's offer of a closed link is nothing at all
////   (`0x140479560.anim_state_exit`).

import genesis_prime/game/activate
import genesis_prime/game/departures
import genesis_prime/game/prerequisite
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/table/creature2
import genesis_prime/table/id.{type Creature2Id, Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict
import gleam/list
import gleam/result

/// The index a questAnim column holds to name the quest alone.
const quest_alone = -1

/// The objectives a creature's row links it to, as (quest id, objective index), the
/// questAnim pair first. A creature the tables lack has none.
pub fn links(
  tables tables: table_store.Tables,
  creature_id creature_id: Creature2Id,
) -> List(#(Int, Int)) {
  case creature2.get(tables:, id: creature_id) {
    Error(Nil) -> []
    Ok(row) ->
      list.append(
        quest_anim_links(row:),
        prerequisite_links(
          activations: activate.activations(tables:),
          prerequisite_id: row.prerequisite_id_anim_state,
        ),
      )
  }
}

/// Whether the creature's row names a quest animation or an animation prerequisite
/// (`Creature2.objective_link`): the client builds and offers such a creature whatever
/// its faction, while the objective it serves is open (`0x140456960.faction`,
/// `0x140479560.faction`, `0x14039d4a0.faction`).
pub fn has_link(row row: creature2.Creature2) -> Bool {
  row.quest_anim_state_id != 0 || row.prerequisite_id_anim_state != 0
}

fn quest_anim_links(row row: creature2.Creature2) -> List(#(Int, Int)) {
  case
    row.quest_anim_state_id != 0
    && row.quest_anim_objective_index != quest_alone
  {
    True -> [#(row.quest_anim_state_id, row.quest_anim_objective_index)]
    False -> []
  }
}

/// The (quest, index) pairs a Prerequisite row names as open (`prerequisite.objective_links`);
/// none for 0 or for an id the table has no row for.
fn prerequisite_links(
  activations activations: activate.Activations,
  prerequisite_id prerequisite_id: Int,
) -> List(#(Int, Int)) {
  dict.get(activations.prerequisites, prerequisite_id)
  |> result.map(fn(held) { prerequisite.objective_links(prerequisite: held) })
  |> result.unwrap([])
}

/// Whether the quest log opens the creature's link, as the client's offer of its
/// activation reads it, for the subject the creature's prerequisite is checked for (the
/// player, with the creature as the second unit). The checklist index is the creature's
/// bit in a checklist objective's mask. A departures terminal is closed whenever its
/// faction's travel objective is not open (`departures.link`), as well as when its own
/// columns close it.
pub fn of(
  tables tables: table_store.Tables,
  activations activations: activate.Activations,
  subject subject: prerequisite.Subject,
  quests quests: QuestLog,
  row row: creature2.Creature2,
  checklist_index checklist_index: Int,
) -> activate.Link {
  use <- bool.guard(when: !has_link(row:), return: activate.NoLink)
  use <- bool.guard(
    when: departures.link(tables:, quests:, creature_id: Creature2Id(row.id))
      == Ok(activate.ClosedLink),
    return: activate.ClosedLink,
  )
  let quest_anim_open = case row.quest_anim_state_id {
    0 -> True
    quest_id ->
      quest_anim_is_open(
        tables:,
        quests:,
        quest_id:,
        index: row.quest_anim_objective_index,
        checklist_index:,
      )
  }
  case quest_anim_open, row.prerequisite_id_anim_state {
    False, _ -> activate.ClosedLink
    True, 0 -> activate.OpenLink
    True, prerequisite_id ->
      prerequisite_link(activations:, subject:, prerequisite_id:)
  }
}

/// The link a prerequisite column decides: open when the prerequisite passes, closed when
/// it fails or the table has no row for it (`Prerequisite.flags`: a missing id fails),
/// unread when a condition the server does not read decides it.
fn prerequisite_link(
  activations activations: activate.Activations,
  subject subject: prerequisite.Subject,
  prerequisite_id prerequisite_id: Int,
) -> activate.Link {
  case dict.get(activations.prerequisites, prerequisite_id) {
    Error(Nil) -> activate.ClosedLink
    Ok(held) ->
      case prerequisite.check(prerequisite: held, subject:) {
        prerequisite.Passes -> activate.OpenLink
        prerequisite.Fails -> activate.ClosedLink
        prerequisite.NotRead(prerequisite_type:) ->
          activate.UnreadLink(prerequisite_type:)
      }
  }
}

/// `QuestAnimInteractKind` answers Interact: the quest is Accepted and the index is -1,
/// or the objective at the index is open and its unit's bit is not marked.
fn quest_anim_is_open(
  tables tables: table_store.Tables,
  quests quests: QuestLog,
  quest_id quest_id: Int,
  index index: Int,
  checklist_index checklist_index: Int,
) -> Bool {
  quest_log.quest_of(tables:, id: quest_id)
  |> result.map(fn(quest) {
    quest_log.state(log: quests, quest:) == accepted
    && {
      index == quest_alone
      || {
        quest_log.objective_open(log: quests, quest:, index:)
        && !quest_log.is_marked(
          log: quests,
          quest:,
          index:,
          bit: checklist_index,
        )
      }
    }
  })
  |> result.unwrap(False)
}

/// The state number of an Accepted quest (`quest_log.state`).
const accepted = 1
