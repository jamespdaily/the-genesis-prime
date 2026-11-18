//// The visible scripted objectives that ask only to kill: the rows of the `kill_objective`
//// content table the load checks. A QuestObjective of type 5 is done only by the server's
//// 0x361 (`QuestObjective.type.5`), and the client counts a unit of the objective's reward
//// pane TargetGroup for an objective of any type (`0x140550c50`), so the server counts a
//// kill of a pane creature for a row of this table (`objective.counts`) and the
//// objective's creatures stand at its marker (`objective_spawn.place`). No client table or
//// code says which type 5 objectives ask only for a kill: each is a row the table states
//// with its reason.
////
//// ```
//// content.load: ids ─▶ select(ids, tables) ─▶ Set(objective id) | refusals (the load stops)
//// each connection's settings ─▶ the set ─▶ objective.advance(Killed) ─▶ a pane kill counts one
//// ```
////
//// - **A row must be a kill the server can see done.** The objective is a visible,
////   required script no creature links (`objective.visible_script_broken` is empty in
////   every quest that lists it), it has a marker whose WorldLocation2 row exists, its
////   reward pane lists a creature of creation type 0, which the server fights, and no
////   spell effect or item names it (`objective_action.named`): an objective a cast
////   advances stays open until the cast counts, not when a creature dies.
////
//// - **A gap.** The load has no spawn table, so it does not check that a creature of the pane
////   starts in its marker's world and that a player can fight it; the world-data check of
////   `./check` does. A row added for a creature that never starts loads, and stops a quest
////   that completes on accept from completing until that check runs.
////
//// The failure points are those of `objective_row`.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/objective
import genesis_prime/game/objective_action
import genesis_prime/game/objective_row
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import genesis_prime/world_map/creation_type
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// The table's name in the log and in a refusal.
pub const table = "kill_objective"

/// The QuestObjective ids the table's rows hold, or every row the load refuses.
pub fn select(
  ids ids: List(Int),
  tables tables: table_store.Tables,
) -> Result(Set(Int), List(Refusal)) {
  objective_row.select(
    table:,
    ids:,
    tables:,
    broken: fn(tables, quest, index, listed_objective) {
      list.flatten([
        objective.visible_script_broken(
          tables:,
          quest_id: quest.id,
          index:,
          objective: listed_objective,
        ),
        case
          has_marker_row(tables:, objective_id: listed_objective.objective_id)
        {
          True -> []
          False -> [
            "none of its worldLocationsIdIndicator markers names a WorldLocation2 row, so no creature can stand at it",
          ]
        },
        pane_broken(tables:, objective: listed_objective),
        case objective_action.named(tables:, quest_id: quest.id, index:) {
          True -> [
            "a spell effect or an item names it, so a cast advances it, not a kill",
          ]
          False -> []
        },
      ])
    },
  )
}

fn has_marker_row(
  tables tables: table_store.Tables,
  objective_id objective_id: Int,
) -> Bool {
  case quest_objective.get(tables:, id: QuestObjectiveId(objective_id)) {
    Ok(row) -> place_objective.markers(tables:, objective: row) != []
    Error(Nil) -> False
  }
}

/// What is wrong with the reward pane as the list of units a kill counts for: none, a pane
/// that lists no creature, or one whose creatures the server never fights.
fn pane_broken(
  tables tables: table_store.Tables,
  objective objective: quest_log.Objective,
) -> List(String) {
  let id = "QuestObjective " <> int.to_string(objective.objective_id)
  case objective.reward_pane {
    0 -> [id <> " has no reward pane, so no unit is the one to kill"]
    pane ->
      case target_group.listed_creatures(tables:, group: pane) {
        [] -> [
          id
          <> "'s reward pane TargetGroup "
          <> int.to_string(pane)
          <> " lists no creature, so no kill counts",
        ]
        creatures ->
          case list.any(creatures, fights(tables:, creature_id: _)) {
            True -> []
            False -> [
              id
              <> "'s reward pane lists no creature of creation type 0, which the server fights",
            ]
          }
      }
  }
}

fn fights(
  tables tables: table_store.Tables,
  creature_id creature_id: Int,
) -> Bool {
  case creature2.get(tables, Creature2Id(creature_id)) {
    Ok(creature) ->
      creation_type.kind_of(creature.creation_type_enum)
      == creation_type.NonPlayer
    Error(Nil) -> False
  }
}
