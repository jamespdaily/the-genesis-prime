//// The visible scripted objectives the server leaves open: the rows of the
//// `held_objective` content table the load checks. A QuestObjective of type 5 is done
//// only by the server's 0x361 (`QuestObjective.type.5`), and the server completes a
//// visible one with no marker once its quest's other required objectives are done
//// (`objective.stand_in_scripts`), except the ones only an instance run or a PvP match
//// could complete; no client table or code says which those are, so each is a row the
//// table states with its reason.
////
//// ```
//// content.load: rows ─▶ select(rows, tables) ─▶ Set(objective id) | refusals (the load stops)
//// each connection's settings ─▶ the set ─▶ objective.settle ─▶ a held script stays open
//// ```
////
//// - **A held row must be a stand-in.** The set holds only objectives the rule would
////   otherwise complete (`objective.visible_script_broken` is empty in every quest that
////   lists the objective), so a row cannot hold back a script the server never completes
////   and a marked, linked, hidden or optional objective cannot be listed by mistake.
////
//// What happens at each failure point:
////
//// | Point | What happens |
//// |---|---|
//// | a row has no QuestObjective row | the load stops, naming the row |
//// | no Quest2 row lists the objective | the load stops, naming the row |
//// | the objective is not a visible stand-in in a quest that lists it | the load stops, naming the row, the quest and each rule broken |

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/game/objective
import genesis_prime/game/quest_log
import genesis_prime/table/id.{QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/set.{type Set}
import gleam/string

/// The table's name in the log and in a refusal.
pub const table = "held_objective"

/// One row of the held_objective table as the load reads it: a QuestObjective id.
pub type Row {
  Row(objective_id: Int)
}

/// The QuestObjective ids the rows hold, or every row the load refuses.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Result(Set(Int), List(Refusal)) {
  let listed = case rows {
    [] -> dict.new()
    _ -> listed_by(tables:)
  }
  let refusals =
    list.filter_map(rows, fn(row) {
      case broken(row:, tables:, listed:) {
        [] -> Error(Nil)
        rules ->
          Ok(Refusal(
            table:,
            row: RowId(row.objective_id),
            rule: string.join(rules, "; "),
          ))
      }
    })
  case refusals {
    [] -> Ok(set.from_list(list.map(rows, fn(row) { row.objective_id })))
    _ -> Error(refusals)
  }
}

/// The places each objective is listed at, as its quest and its index there: the quests
/// as the log reads them, those with an unreadable row left out.
fn listed_by(
  tables tables: table_store.Tables,
) -> Dict(Int, List(#(quest_log.Quest, Int, quest_log.Objective))) {
  quest2.all(tables)
  |> list.filter_map(fn(row) { quest_log.quest_of(tables:, id: row.id) })
  |> list.fold(dict.new(), fn(listed, quest) {
    list.index_fold(quest.objectives, listed, fn(listed, objective, index) {
      dict.upsert(listed, objective.objective_id, fn(places) {
        [#(quest, index, objective), ..option.unwrap(places, [])]
      })
    })
  })
}

/// The rules a row breaks: none when the objective is a visible stand-in in every quest
/// that lists it.
fn broken(
  row row: Row,
  tables tables: table_store.Tables,
  listed listed: Dict(Int, List(#(quest_log.Quest, Int, quest_log.Objective))),
) -> List(String) {
  let id = row.objective_id
  case quest_objective.get(tables:, id: QuestObjectiveId(id)) {
    Error(Nil) -> [
      "the client's QuestObjective table has no row " <> int.to_string(id),
    ]
    Ok(_) ->
      case dict.get(listed, id) {
        Error(Nil) | Ok([]) -> [
          "no Quest2 row lists the objective, so no quest would complete it",
        ]
        Ok(places) ->
          list.flat_map(places, fn(place) {
            let #(quest, index, listed_objective) = place
            objective.visible_script_broken(
              tables:,
              quest_id: quest.id,
              index:,
              objective: listed_objective,
            )
            |> list.map(fn(rule) {
              "in Quest2 " <> int.to_string(quest.id) <> ": " <> rule
            })
          })
      }
  }
}
