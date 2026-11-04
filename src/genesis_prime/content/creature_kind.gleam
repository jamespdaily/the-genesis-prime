//// The creature_kind table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/world_map/creature_kind),
//// and the kinds put into one persistent term under the load's key. It is the
//// second content table and follows the spawn's pattern (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ creature_kind.select(rows, tables) ─▶ put(key, kinds)
//// a map's and a creature's start ─▶ kinds(key) ─▶ Kinds: no copy, no query
//// ```
////
//// - **The term** is one value for the whole table: the default and each creature's
////   own kind, put once.
//// - **The query** is `sql/load_creature_kinds.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/creature_kind.{type Kinds, type Row, Row}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "creature_kind"

/// Every row of the creature_kind table, in creature id order, or why the query
/// failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_creature_kinds(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(creature_id: row.creature_id, respawn_ms: row.respawn_ms)
    })
  })
}

/// Writes the kinds under the key, once.
pub fn put(key key: Key, kinds kinds: Kinds) -> Nil {
  store.put_content(key:, table:, id: 0, value: kinds)
}

/// The kinds the load put under the key. The load puts the term before the tree
/// starts, so a reader that finds none is a bug and crashes.
pub fn kinds(key key: Key) -> Kinds {
  store.content(key:, table:, id: 0)
}
