//// The class_resource table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/game/class_resource
//// `select`), and the classes' resources put into one persistent term under the
//// load's key. It follows the pattern of the other content tables
//// (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ class_resource.select(rows) ─▶ put(key, classes)
//// the game listener's start ─▶ classes(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_class_resources.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/class_resource.{type Classes, type Row, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "class_resource"

/// Every row of the class_resource table, in class and name order, or why the
/// query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_class_resources(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        class_id: row.class_id,
        name: row.name,
        value: row.value,
        unit: row.unit,
      )
    })
  })
}

/// Writes the classes' resources under the key, once.
pub fn put(key key: Key, classes classes: Classes) -> Nil {
  store.put_content(key:, table:, id: 0, value: classes)
}

/// The classes' resources the load put under the key. The load puts the term
/// before the tree starts, so a reader that finds none is a bug and crashes.
pub fn classes(key key: Key) -> Classes {
  store.content(key:, table:, id: 0)
}
