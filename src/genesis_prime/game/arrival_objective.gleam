//// The visible scripted objectives that ask only to reach a place: the rows of the
//// `arrival_objective` content table the load checks. A QuestObjective of type 5 is done
//// only by the server's 0x361 (`QuestObjective.type.5`) and the client draws its marker as
//// the destination whatever it asks (`0x140553890`), so the server completes a row of this
//// table when the player stands at one of its markers (`objective.settle`), and no client
//// table or code says which objectives ask only that: each is a row the table states as
//// a server choice.
////
//// ```
//// content.load: ids ─▶ select(ids, tables) ─▶ Set(objective id) | refusals (the load stops)
//// each connection's settings ─▶ the set ─▶ objective.settle ─▶ a position at a marker completes it
//// ```
////
//// - **A row must be a place the position can reach.** The objective is a visible,
////   required script no creature links (`objective.visible_script_broken` is empty in every
////   quest that lists it), it has a marker whose WorldLocation2 row exists, and no spell
////   effect or item names it (`objective_action.named`): an objective a cast advances
////   stays open until the cast counts, not when a player walks in.
////
//// The failure points are those of `objective_row`.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/objective
import genesis_prime/game/objective_action
import genesis_prime/game/objective_row
import genesis_prime/game/place_objective
import genesis_prime/table/id.{QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import gleam/list
import gleam/set.{type Set}

/// The table's name in the log and in a refusal.
pub const table = "arrival_objective"

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
            "none of its worldLocationsIdIndicator markers names a WorldLocation2 row, so no position is at it",
          ]
        },
        case objective_action.named(tables:, quest_id: quest.id, index:) {
          True -> [
            "a spell effect or an item names it, so a cast advances it, not an arrival",
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
