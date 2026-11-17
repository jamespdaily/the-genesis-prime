//// The creature_auto_attack table as the server reads it at start: one query for every row,
//// the rows handed to the pure check beside the creature_kind rows
//// (genesis_prime/world_map/creature_kind `select`), which puts each creature's
//// auto-attacks into its kind.
////
//// ```
//// content.load ─▶ rows(db) ─▶ creature_kind.select(kind_rows, special_rows, auto_attack_rows, tables) ─▶ Kind.attack_spell4_id, Kind.alternate_spell4_ids
//// ```
////
//// - **The query** is `sql/load_creature_auto_attacks.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.
//// - **No term of its own**: the auto-attacks live in the kinds
////   (genesis_prime/content/creature_kind `put`).

import genesis_prime/content/sql
import genesis_prime/world_map/creature_auto_attack.{type Row, Row}
import gleam/list
import gleam/result
import pog

/// The table's name in the log.
pub const table = creature_auto_attack.table

/// Every row of the creature_auto_attack table, in creature id and turn order, or why the
/// query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_creature_auto_attacks(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        creature_id: row.creature_id,
        spell4_id: row.spell4_id,
        order_index: row.order_index,
      )
    })
  })
}
