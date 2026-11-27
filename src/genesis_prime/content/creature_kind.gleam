//// The creature_kind table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/world_map/creature_kind),
//// and the kinds put into one persistent term under the load's key. It is the
//// second content table and follows the spawn's pattern (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ creature_kind.select(rows, special_rows, tables) ─▶ put(key, kinds)
//// a map's and a creature's start ─▶ kinds(key) ─▶ Kinds: no copy, no query
//// ```
////
//// - **The term** is one value for the whole table: the default and each creature's
////   own kind, put once.
//// - **The query** is `sql/load_creature_kinds.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/content/sql
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/creature_kind.{
  type Kinds, type Row, GuardSpells, Row,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "creature_kind"

/// Why the creature_kind rows were not read.
pub type RowsError {
  /// The query failed.
  QueryFailed(reason: pog.QueryError)
  /// Rows the table's checks would have refused: each names its creature.
  RowsRefused(refusals: List(Refusal))
}

/// Every row of the creature_kind table, in creature id order, or why they were not
/// read: the query failed, or rows hold a guard without an opening or an opening
/// without a guard (`row_of`), every such row named.
pub fn rows(db db: pog.Connection) -> Result(List(Row), RowsError) {
  use returned <- result.try(
    sql.load_creature_kinds(db) |> result.map_error(QueryFailed),
  )
  let #(rows, refusals) =
    list.map(returned.rows, row_of)
    |> result.partition
  case refusals {
    [] -> Ok(list.reverse(rows))
    refusals -> Error(RowsRefused(refusals: list.reverse(refusals)))
  }
}

/// The row the query returned, or the refusal of a row with a guard and no opening
/// or an opening and no guard (`creature_kind_guard_and_opening_together`).
pub fn row_of(row row: sql.LoadCreatureKindsRow) -> Result(Row, Refusal) {
  use guard <- result.map(case row.guard_spell4_id, row.opening_spell4_id {
    Some(guard_spell4_id), Some(opening_spell4_id) ->
      Ok(Some(GuardSpells(guard_spell4_id:, opening_spell4_id:)))
    None, None -> Ok(None)
    Some(..), None | None, Some(..) ->
      Error(Refusal(
        table:,
        row: RowId(row.creature_id),
        rule: "a guard and an opening are both set or both left out",
      ))
  })
  Row(
    creature_id: row.creature_id,
    respawn_ms: row.respawn_ms,
    attack_spell4_id: row.attack_spell4_id,
    attack_interval_ms: row.attack_interval_ms,
    guard:,
  )
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
