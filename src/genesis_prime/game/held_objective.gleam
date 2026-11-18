//// The visible scripted objectives the server leaves open: the rows of the
//// `held_objective` content table the load checks. A QuestObjective of type 5 is done
//// only by the server's 0x361 (`QuestObjective.type.5`), and the server completes a
//// visible one that no creature links by a stand-in or, for a listed place, by arrival
//// (`objective.script_of`), except the ones only an instance run or a PvP match could
//// complete; no client table or code says which those are, so each is a row the table
//// states with its reason.
////
//// ```
//// content.load: ids ─▶ select(ids, tables) ─▶ Set(objective id) | refusals (the load stops)
//// each connection's settings ─▶ the set ─▶ objective.settle ─▶ a held script stays open
//// ```
////
//// - **A held row must be a script the rules would complete.** The set holds only
////   objectives that are type 5, visible, required and linked by no creature
////   (`objective.visible_script_broken` is empty in every quest that lists the objective),
////   so a linked, hidden, optional or other-type objective cannot be listed by mistake. A
////   marker, a place row or a spell that names the objective does not stop a row: the
////   server holds each of them back.
////
//// The failure points are those of `objective_row`.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/objective
import genesis_prime/game/objective_row
import genesis_prime/table/loader/store as table_store
import gleam/set.{type Set}

/// The table's name in the log and in a refusal.
pub const table = "held_objective"

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
      objective.visible_script_broken(
        tables:,
        quest_id: quest.id,
        index:,
        objective: listed_objective,
      )
    },
  )
}
