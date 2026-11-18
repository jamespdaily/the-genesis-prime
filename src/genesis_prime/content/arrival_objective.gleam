//// The arrival_objective table as the server reads it at start: one query for every row,
//// the rows handed to the pure check (genesis_prime/game/arrival_objective `select`), and the
//// set of QuestObjective ids they hold put into one persistent term under the load's key.
//// It follows the pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ arrival_objective.select(rows, tables) ─▶ put(key, ids)
//// the game listener's start ─▶ arrivals(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_arrival_objectives.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/arrival_objective.{type Row, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import gleam/set.{type Set}
import pog

/// The table's name in the log and in a term.
pub const table = arrival_objective.table

/// Every row of the arrival_objective table, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_arrival_objectives(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) { Row(objective_id: row.objective_id) })
  })
}

/// Writes the QuestObjective ids of the places under the key, once.
pub fn put(key key: Key, arrivals arrivals: Set(Int)) -> Nil {
  store.put_content(key:, table:, id: 0, value: arrivals)
}

/// The QuestObjective ids of the places the load put under the key. The load puts the term
/// before the tree starts, so a reader that finds none is a bug and crashes.
pub fn arrivals(key key: Key) -> Set(Int) {
  store.content(key:, table:, id: 0)
}
