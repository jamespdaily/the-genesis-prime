//// The projector_landing table as the server reads it at start: one query for every row,
//// the rows handed to the pure check (genesis_prime/game/projector `select`), and the
//// landings they make put into one persistent term under the load's key. It follows the
//// pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ projector.select(rows, tables) ─▶ put(key, landings)
//// the game listener's start ─▶ landings(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_projector_landings.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/projector.{type Landings, type Row, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = projector.table

/// Every row of the projector_landing table, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_projector_landings(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        creature_id: row.creature_id,
        faction_enum: row.faction_enum,
        objective_id: row.objective_id,
        world_location2_id: row.world_location2_id,
      )
    })
  })
}

/// Writes the projector landings under the key, once.
pub fn put(key key: Key, landings landings: Landings) -> Nil {
  store.put_content(key:, table:, id: 0, value: landings)
}

/// The projector landings the load put under the key. The load puts the term before the
/// tree starts, so a reader that finds none is a bug and crashes.
pub fn landings(key key: Key) -> Landings {
  store.content(key:, table:, id: 0)
}
