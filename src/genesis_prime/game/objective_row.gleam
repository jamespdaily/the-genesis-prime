//// The load's check of a content table whose rows each name a QuestObjective: the
//// objective's row and a Quest2 that lists it must exist, and a rule of the table must hold
//// for the objective at every place a quest lists it. `held_objective`, `arrival_objective`,
//// `kill_objective` and `click_objective` give the rule; the last two share the check of an
//// objective's marker and of its reward pane (`marker_broken`, `pane_broken`).
////
//// ```
//// content.load: ids ─▶ select(table, ids, tables, broken) ─▶ Set(objective id) | refusals
//// ```
////
//// What happens at each failure point:
////
//// | Point | What happens |
//// |---|---|
//// | an id has no QuestObjective row | the load stops, naming the row |
//// | no Quest2 row lists the objective | the load stops, naming the row |
//// | the table's rule fails at a place a quest lists | the load stops, naming the row, the quest and each rule broken |

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/game/place_objective
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/shared/quest_row
import genesis_prime/table/id.{QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleam/string

/// The rules a table's rule breaks for the objective at `index` of the quest: none when it
/// holds.
pub type Broken =
  fn(table_store.Tables, quest_row.Quest, Int, quest_row.Objective) ->
    List(String)

/// The QuestObjective ids of a table's rows, or every row the load refuses.
pub fn select(
  table table: String,
  ids ids: List(Int),
  tables tables: table_store.Tables,
  broken broken: Broken,
) -> Result(Set(Int), List(Refusal)) {
  let listed = case ids {
    [] -> dict.new()
    _ -> quest_log.listed_objectives(tables:)
  }
  let refusals =
    list.filter_map(ids, fn(objective_id) {
      case rules_broken(objective_id:, tables:, listed:, broken:) {
        [] -> Error(Nil)
        rules ->
          Ok(Refusal(
            table:,
            row: RowId(objective_id),
            rule: string.join(rules, "; "),
          ))
      }
    })
  case refusals {
    [] -> Ok(set.from_list(ids))
    _ -> Error(refusals)
  }
}

fn rules_broken(
  objective_id objective_id: Int,
  tables tables: table_store.Tables,
  listed listed: Dict(Int, List(#(quest_row.Quest, Int, quest_row.Objective))),
  broken broken: Broken,
) -> List(String) {
  case quest_objective.get(tables:, id: QuestObjectiveId(objective_id)) {
    Error(Nil) -> [
      "the client's QuestObjective table has no row "
      <> int.to_string(objective_id),
    ]
    Ok(_) ->
      case dict.get(listed, objective_id) {
        Error(Nil) | Ok([]) -> [
          "no Quest2 row lists the objective, so no quest would complete it",
        ]
        Ok(places) ->
          list.flat_map(places, fn(place) {
            let #(quest, index, objective) = place
            broken(tables, quest, index, objective)
            |> list.map(fn(rule) {
              "in Quest2 " <> int.to_string(quest.id) <> ": " <> rule
            })
          })
      }
  }
}

/// What is wrong with an objective's markers as the places creatures stand at for a table's
/// rule: none when one of its worldLocationsIdIndicator markers names a WorldLocation2 row.
pub fn marker_broken(
  tables tables: table_store.Tables,
  objective_id objective_id: Int,
) -> List(String) {
  let has_marker_row = case
    quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
  {
    Ok(row) -> place_objective.markers(tables:, objective: row) != []
    Error(Nil) -> False
  }
  case has_marker_row {
    True -> []
    False -> [
      "none of its worldLocationsIdIndicator markers names a WorldLocation2 row, so no creature can stand at it",
    ]
  }
}

/// What is wrong with the reward pane as the list of units a table's rule counts: none, a
/// pane that lists no creature, or one that lists no creature `wanted` holds for.
/// `action` is the verb the rule counts ("kill", "click") and `missing` says what the
/// pane lacks.
pub fn pane_broken(
  tables tables: table_store.Tables,
  objective objective: quest_row.Objective,
  action action: String,
  wanted wanted: fn(Int) -> Bool,
  missing missing: String,
) -> List(String) {
  let id = "QuestObjective " <> int.to_string(objective.objective_id)
  case objective.reward_pane {
    0 -> [id <> " has no reward pane, so no unit is the one to " <> action]
    pane ->
      case target_group.listed_creatures(tables:, group: pane) {
        [] -> [
          id
          <> "'s reward pane TargetGroup "
          <> int.to_string(pane)
          <> " lists no creature, so no "
          <> action
          <> " counts",
        ]
        creatures ->
          case list.any(creatures, wanted) {
            True -> []
            False -> [id <> "'s reward pane lists " <> missing]
          }
      }
  }
}
