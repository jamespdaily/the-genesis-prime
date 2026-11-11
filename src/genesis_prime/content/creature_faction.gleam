//// The creature_faction table as the server reads it at start: one query for every
//// row, handed to the pure check (genesis_prime/world_map/creature_faction).
//// The query is `sql/load_creature_factions.sql`; nothing queries the table during
//// play.

import genesis_prime/content/sql
import genesis_prime/world_map/creature_faction.{type Row, Row}
import gleam/list
import gleam/result
import pog

/// The table's name in the log.
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
