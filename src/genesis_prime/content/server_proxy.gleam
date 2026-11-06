//// The server_proxy table as the server reads it at start: one query for every
//// row, the rows handed to the pure check (genesis_prime/game/server_proxy `select`),
//// and the server's Proxies put into one persistent term under the load's key. It
//// follows the pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ server_proxy.select(rows, tables, plans) ─▶ put(key, proxies)
//// the game listener's start ─▶ proxies(key) ─▶ each connection's settings: no copy, no query
//// ```
////
//// - **The query** is `sql/load_server_proxies.sql`, run by the load's own pool
////   before the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/server_proxy.{type Row, type ServerProxies, Row}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "server_proxy"

/// Every row of the server_proxy table, in key order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_server_proxies(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        spell4_base_id: row.spell4_base_id,
        phase: row.phase,
        spell4_id: row.spell4_id,
      )
    })
  })
}

/// Writes the server's Proxies under the key, once.
pub fn put(key key: Key, proxies proxies: ServerProxies) -> Nil {
  store.put_content(key:, table:, id: 0, value: proxies)
}

/// The server's Proxies the load put under the key. The load puts the term before
/// the tree starts, so a reader that finds none is a bug and crashes.
pub fn proxies(key key: Key) -> ServerProxies {
  store.content(key:, table:, id: 0)
}
