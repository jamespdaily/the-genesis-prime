//// The item_objective table as the server reads it at start: one query for every row,
//// the rows handed to the pure check (genesis_prime/game/item_objective_table `select`), and the
//// objectives with what each asks put into one persistent term under the load's key. It
//// follows the pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ item_objective_table.select(rows, tables, taken) ─▶ put(key, wanted)
//// the game listener's start ─▶ wanted(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_item_objectives.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.
//// - **The kind column** holds `equip` or `buy`, which the table's check constraint keeps.

import genesis_prime/content/sql
import genesis_prime/game/item_objective.{type Wanted}
import genesis_prime/game/item_objective_table.{type Row, Buy, Equip, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = item_objective_table.table

/// Every row of the item_objective table, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_item_objectives(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        objective_id: row.objective_id,
        kind: case row.kind {
          "buy" -> Buy
          "equip" -> Equip
          other ->
            panic as {
              "item_objective.kind is equip or buy by the table's check, not "
              <> other
            }
        },
        item2_id: row.item2_id,
        creature2_id: row.creature2_id,
      )
    })
  })
}

/// Writes what each item objective asks, by QuestObjective id, under the key, once.
pub fn put(key key: Key, wanted wanted: Dict(Int, Wanted)) -> Nil {
  store.put_content(key:, table:, id: 0, value: wanted)
}

/// What each item objective asks, as the load put it under the key. The load puts the term
/// before the tree starts, so a reader that finds none is a bug and crashes.
pub fn wanted(key key: Key) -> Dict(Int, Wanted) {
  store.content(key:, table:, id: 0)
}
