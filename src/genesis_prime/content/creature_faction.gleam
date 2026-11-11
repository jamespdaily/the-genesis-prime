//// The creature_faction table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/world_map/creature_faction),
//// and the factions put into one persistent term under the load's key. It follows
//// the pattern of `creature_kind` (genesis_prime/content/creature_kind).
////
//// ```
//// content.load ─▶ rows(db) ─▶ creature_faction.select(rows, tables) ─▶ put(key, factions)
//// ```
////
//// - **The term** is one value for the whole table, put once.
//// - **The query** is `sql/load_creature_factions.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/creature_faction.{type Factions, type Row, Row}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = creature_faction.table

/// Every row of the creature_faction table, in creature id order, or why the query
/// failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_creature_factions(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(creature_id: row.creature_id, faction_id: row.faction_id)
    })
  })
}

/// Writes the factions under the key, once.
pub fn put(key key: Key, factions factions: Factions) -> Nil {
  store.put_content(key:, table:, id: 0, value: factions)
}

/// The factions the load put under the key. The load puts the term before the tree
/// starts, so a reader that finds none is a bug and crashes.
pub fn factions(key key: Key) -> Factions {
  store.content(key:, table:, id: 0)
}
