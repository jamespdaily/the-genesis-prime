//// The game_number table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/world_map/game_number),
//// and the numbers put into one persistent term under the load's key. It follows
//// the pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ game_number.select(rows, sight.range) ─▶ put(key, numbers)
//// a map's and a creature's start ─▶ numbers(key) ─▶ GameNumbers: no copy, no query
//// ```
////
//// - **The query** is `sql/load_game_numbers.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/game_number.{type GameNumbers, type Row, Row}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "game_number"

/// Every row of the game_number table, in name order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_game_numbers(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(name: row.name, value: row.value, unit: row.unit)
    })
  })
}

/// Writes the numbers under the key, once.
pub fn put(key key: Key, numbers numbers: GameNumbers) -> Nil {
  store.put_content(key:, table:, id: 0, value: numbers)
}

/// The numbers the load put under the key. The load puts the term before the tree
/// starts, so a reader that finds none is a bug and crashes.
pub fn numbers(key key: Key) -> GameNumbers {
  store.content(key:, table:, id: 0)
}
