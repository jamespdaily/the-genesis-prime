//// The load's check of a content table whose rows each name a QuestObjective: the
//// objective's row and a Quest2 that lists it must exist, and a rule of the table must hold
//// for the objective at every place a quest lists it. `held_objective`,
//// `arrival_objective` and `item_objective_table` give the rule.
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
import genesis_prime/game/quest_log
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
  fn(table_store.Tables, quest_log.Quest, Int, quest_log.Objective) ->
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
  listed listed: Dict(Int, List(#(quest_log.Quest, Int, quest_log.Objective))),
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
