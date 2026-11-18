//// The content tables whose rows each name a QuestObjective (`held_objective`,
//// `arrival_objective`, `kill_objective`, `click_objective`), as the server reads them at
//// start: one query for every row of them, each table's ids handed to its pure check
//// (genesis_prime/game, the table's `select`), and the set of ids that check accepts put
//// into one persistent term per table under the load's key.
////
//// ```
//// content.load ─▶ rows(db) ─▶ check(rows, tables) ─▶ Checked(sets, refusals) ─▶ put(key, checked)
//// the game listener's start ─▶ read(key, table) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_objective_sets.sql`, run by the load's own pool before the
////   tree starts; nothing queries the tables during play.
//// - **A table of this kind** adds a line to the query, an entry to `checks`, a migration, and
////   a field to the connection's settings that its rule reads (genesis_prime/game/connection/state
////   and genesis_prime), and a line to the test support that puts empty sets
////   (`spawn_support.put_worlds`); `content.gleam` and this module's other functions do not change.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/content/sql
import genesis_prime/game/arrival_objective
import genesis_prime/game/click_objective
import genesis_prime/game/held_objective
import genesis_prime/game/kill_objective
import genesis_prime/table/loader/store.{type Key}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/set.{type Set}
import pog

/// The name the load gives a failed query of these tables, which one query reads together.
pub const query_name =
  "held_objective, arrival_objective, kill_objective and click_objective"

/// The QuestObjective ids of each table's rows, by the table's name.
pub opaque type Rows {
  Rows(by_table: Dict(String, List(Int)))
}

/// Every row of the tables, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(Rows, pog.QueryError) {
  sql.load_objective_sets(db)
  |> result.map(fn(returned) {
    Rows(
      by_table: list.group(returned.rows, fn(row) { row.table_name })
      |> dict.map_values(fn(_table, rows) {
        list.map(rows, fn(row) { row.objective_id })
      }),
    )
  })
}

/// The QuestObjective ids of the table's rows, in key order; none for a table with no rows.
pub fn ids(rows rows: Rows, table table: String) -> List(Int) {
  result.unwrap(dict.get(rows.by_table, table), or: [])
}

/// Writes the QuestObjective ids a table's check accepted under the key, once.
pub fn put(
  key key: Key,
  table table: String,
  objectives objectives: Set(Int),
) -> Nil {
  store.put_content(key:, table:, id: 0, value: objectives)
}

/// The QuestObjective ids of the table the load put under the key. The load puts the term
/// before the tree starts, so a reader that finds none is a bug and crashes.
pub fn read(key key: Key, table table: String) -> Set(Int) {
  store.content(key:, table:, id: 0)
}

/// A table's name and the pure check of its rows: the table's `select`.
type Check =
  #(String, fn(List(Int), store.Tables) -> Result(Set(Int), List(Refusal)))

/// Every table of this kind and its check.
fn checks() -> List(Check) {
  [
    #(held_objective.table, fn(ids, tables) {
      held_objective.select(ids:, tables:)
    }),
    #(arrival_objective.table, fn(ids, tables) {
      arrival_objective.select(ids:, tables:)
    }),
    #(kill_objective.table, fn(ids, tables) {
      kill_objective.select(ids:, tables:)
    }),
    #(click_objective.table, fn(ids, tables) {
      click_objective.select(ids:, tables:)
    }),
  ]
}

/// What the checks made of the rows: the set of each table that was accepted, and every row
/// refused.
pub opaque type Checked {
  Checked(accepted: Dict(String, Set(Int)), refusals: List(Refusal))
}

/// Runs each table's check over its rows.
pub fn check(rows rows: Rows, tables tables: store.Tables) -> Checked {
  list.fold(
    checks(),
    Checked(accepted: dict.new(), refusals: []),
    fn(so_far, entry) {
      let #(table, select) = entry
      case select(ids(rows:, table:), tables) {
        Ok(objectives) ->
          Checked(
            ..so_far,
            accepted: dict.insert(so_far.accepted, table, objectives),
          )
        Error(refusals) ->
          Checked(..so_far, refusals: list.append(so_far.refusals, refusals))
      }
    },
  )
}

/// The rows the checks refused, in table order.
pub fn refusals(checked checked: Checked) -> List(Refusal) {
  checked.refusals
}

/// The ids of a table the check accepted; none when it refused a row, so the load that places
/// creatures for the table's objectives (and stops on the refusal) places none.
pub fn accepted(checked checked: Checked, table table: String) -> Set(Int) {
  result.unwrap(dict.get(checked.accepted, table), or: set.new())
}

/// Writes the QuestObjective ids each accepted table holds under the key, once. A table whose
/// check refused a row is not written: the load stops on the refusal.
pub fn put_accepted(key key: Key, checked checked: Checked) -> Nil {
  dict.each(checked.accepted, fn(table, objectives) {
    put(key:, table:, objectives:)
  })
}
