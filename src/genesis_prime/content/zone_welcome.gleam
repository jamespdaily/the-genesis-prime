//// The zone_welcome table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/game/zone_welcome `select`),
//// and the zones' welcomes put into one persistent term under the load's key. It
//// follows the pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ zone_welcome.select(rows, tables) ─▶ put(key, welcomes)
//// the game listener's start ─▶ zone_welcomes(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_zone_welcomes.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/zone_welcome.{type Row, type ZoneWelcomes, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "zone_welcome"

/// Every row of the zone_welcome table, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_zone_welcomes(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(world_zone_id: row.world_zone_id, tutorial_id: row.tutorial_id)
    })
  })
}

/// Writes the zones' welcomes under the key, once.
pub fn put(key key: Key, welcomes welcomes: ZoneWelcomes) -> Nil {
  store.put_content(key:, table:, id: 0, value: welcomes)
}

/// The zones' welcomes the load put under the key. The load puts the term before
/// the tree starts, so a reader that finds none is a bug and crashes.
pub fn zone_welcomes(key key: Key) -> ZoneWelcomes {
  store.content(key:, table:, id: 0)
}
