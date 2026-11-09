//// The vendor and vendor_item tables as the server reads them at start: one query for
//// each, the rows handed to the pure check (genesis_prime/game/vendor `select`), and
//// the vendors put into one persistent term under the load's key. It follows the
//// pattern of the other content tables (genesis_prime/content).
////
//// ```
//// content.load ─▶ rows(db) ─▶ vendor.select(vendors, items, tables) ─▶ put(key, vendors)
//// the game listener's start ─▶ vendors(key) ─▶ each connection's settings, each spawn's check: no copy, no query
//// ```
////
//// - **The queries** are `sql/load_vendors.sql` and `sql/load_vendor_items.sql`, run by
////   the load's own pool before the tree starts; nothing queries the tables during play.

import genesis_prime/content/sql
import genesis_prime/game/vendor.{
  type ItemRow, type VendorRow, type Vendors, ItemRow, VendorRow,
}
import genesis_prime/table/loader/store.{type Key}
import gleam/list
import gleam/result
import pog

/// The tables' name in the log and in a term.
pub const table = "vendor"

/// Every row of the vendor table, in creature order, or why the query failed.
pub fn vendor_rows(
  db db: pog.Connection,
) -> Result(List(VendorRow), pog.QueryError) {
  sql.load_vendors(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      VendorRow(
        creature_id: row.creature_id,
        buy_multiplier: row.buy_multiplier,
        sell_multiplier: row.sell_multiplier,
      )
    })
  })
}

/// Every row of the vendor_item table, in creature and position order, or why the
/// query failed.
pub fn item_rows(
  db db: pog.Connection,
) -> Result(List(ItemRow), pog.QueryError) {
  sql.load_vendor_items(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      ItemRow(
        creature_id: row.creature_id,
        position: row.position,
        item_id: row.item_id,
      )
    })
  })
}

/// Writes the vendors under the key, once.
pub fn put(key key: Key, vendors vendors: Vendors) -> Nil {
  store.put_content(key:, table:, id: 0, value: vendors)
}

/// The vendors the load put under the key. The load puts the term before the tree
/// starts, so a reader that finds none is a bug and crashes.
pub fn vendors(key key: Key) -> Vendors {
  store.content(key:, table:, id: 0)
}
