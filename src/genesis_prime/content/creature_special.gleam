//// The creature_special table as the server reads it at start: one query for every row no import has retired,
//// the rows handed to the pure check beside the creature_kind rows
//// (genesis_prime/shared/creature_kind `select`), which puts each creature's specials
//// into its kind.
////
//// ```
//// content.load ─▶ rows(db) ─▶ creature_kind.select(kind_rows, special_rows, tables) ─▶ Kind.specials
//// ```
////
//// - **The query** is `sql/load_creature_specials.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.
//// - **No term of its own**: the specials live in the kinds
////   (genesis_prime/content/creature_kind `put`).

import genesis_prime/content/sql
import genesis_prime/shared/creature_special.{type Row, Row}
import gleam/list
import gleam/result
import pog

/// The table's name in the log.
pub const table = creature_special.table

/// Every row of the creature_special table that no import has retired, in creature id and list order, or why the
/// query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_creature_specials(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        creature_id: row.creature_id,
        spell4_id: row.spell4_id,
        order_index: row.order_index,
        cooldown_ms: row.cooldown_ms,
      )
    })
  })
}
