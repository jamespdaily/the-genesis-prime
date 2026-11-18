//// The content tables whose rows each name a QuestObjective (`held_objective`,
//// `arrival_objective`, `kill_objective`), as the server reads them at start: one query for
//// every row of them, each table's ids handed to its pure check (genesis_prime/game, the
//// table's `select`), and the set of ids that check accepts put into one persistent term
//// per table under the load's key. A table of this kind adds a line to the query and a
//// check, and no module here.
////
//// ```
//// content.load ─▶ rows(db) ─▶ ids(rows, table) ─▶ <table>.select ─▶ put(key, table, set)
//// the game listener's start ─▶ read(key, table) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_objective_sets.sql`, run by the load's own pool before the
////   tree starts; nothing queries the tables during play.

import genesis_prime/content/sql
import genesis_prime/table/loader/store.{type Key}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/set.{type Set}
import pog

/// The name the load gives a failed query of these tables, which one query reads together.
pub const query_name = "held_objective, arrival_objective and kill_objective"

/// The QuestObjective ids of each table's rows, by the table's name.
pub opaque type Rows {
  Rows(by_table: Dict(String, List(Int)))
}

/// Every row of the tables, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(Rows, pog.QueryError) {
  sql.load_objective_sets(db)
  |> result.map(fn(returned) {
    Rows(
      by_table: list.group(returned.rows, fn(row) { row.table_name })
      |> dict.map_values(fn(_table, rows) {
        list.map(rows, fn(row) { row.objective_id })
      }),
    )
  })
}

/// The QuestObjective ids of the table's rows, in key order; none for a table with no rows.
pub fn ids(rows rows: Rows, table table: String) -> List(Int) {
  result.unwrap(dict.get(rows.by_table, table), or: [])
}

/// Writes the QuestObjective ids a table's check accepted under the key, once.
pub fn put(
  key key: Key,
  table table: String,
  objectives objectives: Set(Int),
) -> Nil {
  store.put_content(key:, table:, id: 0, value: objectives)
}

/// The QuestObjective ids of the table the load put under the key. The load puts the term
/// before the tree starts, so a reader that finds none is a bug and crashes.
pub fn read(key key: Key, table table: String) -> Set(Int) {
  store.content(key:, table:, id: 0)
}
