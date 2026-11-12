//// The tutorial_quest table as the server reads it at start: one query for every row,
//// the rows handed to the pure check (genesis_prime/game/tutorial `select`), and the
//// chain they make put into one persistent term under the load's key. It follows the
//// pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ tutorial.select(rows, tables) ─▶ put(key, chain)
//// the game listener's start ─▶ chain(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_tutorial_quests.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/tutorial.{type Chain, type Row, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = tutorial.table

/// Every row of the tutorial_quest table, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_tutorial_quests(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(quest_id: row.quest_id, follows_quest_id: row.follows_quest_id)
    })
  })
}

/// Writes the tutorial chain under the key, once.
pub fn put(key key: Key, chain chain: Chain) -> Nil {
  store.put_content(key:, table:, id: 0, value: chain)
}

/// The tutorial chain the load put under the key. The load puts the term before the
/// tree starts, so a reader that finds none is a bug and crashes.
pub fn chain(key key: Key) -> Chain {
  store.content(key:, table:, id: 0)
}
