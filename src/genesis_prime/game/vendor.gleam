//// The creatures that sell, and what each sells: a creature of the `vendor` table
//// shows the client its bag icon (create flag 4) and answers a right-click with its
//// stock (genesis_prime/game/interaction). The client's tables hold no stock, so the
//// stock is the content table `vendor_item`, a retail record (genesis_prime/content/vendor).
////
//// ```
//// content.load: vendor rows, item rows ─▶ select(…, tables) ─▶ Vendors | refusals (the load stops)
//// a spawn is built                      ─▶ is_vendor(vendors, creature)  ─▶ create flag 4
//// a right-click (0x7ea kind 0x31)       ─▶ get(vendors, creature)        ─▶ 0x90b with the stock
//// ```
////
//// - **An item's place in the window** is its `position` in the table: the unique id the
////   client names the item by when it buys.
//// - **An item's price** is its buy price (genesis_prime/game/item_price) times the vendor's
////   buy multiplier, cut to a whole credit, the price the client's window shows; the load
////   computes it once and the stock holds it.
//// - **What happens at each failure point:**
////
//// | Point | What happens |
//// |---|---|
//// | a vendor row names a Creature2 the client's table lacks | the load stops, naming `vendor` and the row |
//// | an item row names an Item2 the client's table lacks | the load stops, naming `vendor_item` and the row |
//// | an item row names a creature with no vendor row | the load stops, naming `vendor_item` and the row |
//// | an item row's Item2 has no credit price (another currency, a tradeskill additive, a missing row of its price) | the load stops, naming `vendor_item` and the row (genesis_prime/game/item_price) |

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId, RowName}
import genesis_prime/game/item_price
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  type Creature2Id, type Item2Id, Creature2Id, Item2Id,
}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// One row of the vendor table as the load reads it.
pub type VendorRow {
  VendorRow(creature_id: Int, buy_multiplier: Float, sell_multiplier: Float)
}

/// One row of the vendor_item table as the load reads it.
pub type ItemRow {
  ItemRow(creature_id: Int, position: Int, item_id: Int)
}

/// One item a vendor sells: its place in the window, its Item2 row and its price in credits,
/// the price the client's window shows (genesis_prime/game/item_price).
pub type Stocked {
  Stocked(position: Int, item_id: Item2Id, price: Int)
}

/// What a vendor sells, in position order, and the multipliers it sends.
pub type Vendor {
  Vendor(buy_multiplier: Float, sell_multiplier: Float, items: List(Stocked))
}

/// The vendor window a player has open: the unit it was opened on and what that unit sells.
pub type Opened {
  Opened(unit_id: Int, vendor: Vendor)
}

/// The vendors by their creature.
pub opaque type Vendors {
  Vendors(by_creature: Dict(Creature2Id, Vendor))
}

/// No creature is a vendor.
pub fn none() -> Vendors {
  Vendors(by_creature: dict.new())
}

/// The vendors of the rows over the client's tables, or every refusal: a vendor whose
/// Creature2 row the tables lack, an item whose Item2 row they lack, and an item of a
/// creature that has no vendor row.
pub fn select(
  vendors vendors: List(VendorRow),
  items items: List(ItemRow),
  tables tables: table_store.Tables,
) -> Result(Vendors, List(Refusal)) {
  let vendor_refusals =
    list.filter_map(vendors, fn(row) {
      case creature2.get(tables:, id: Creature2Id(row.creature_id)) {
        Ok(_) -> Error(Nil)
        Error(Nil) ->
          Ok(Refusal(
            table: "vendor",
            row: RowId(row.creature_id),
            rule: "Creature2 "
              <> int.to_string(row.creature_id)
              <> " has no row in the client's table",
          ))
      }
    })
  let known = list.map(vendors, fn(row) { row.creature_id })
  let #(priced, item_refusals) =
    result.partition(
      list.map(items, fn(row) {
        let refused = fn(rule) {
          Refusal(
            table: "vendor_item",
            row: RowName(
              int.to_string(row.creature_id)
              <> "/"
              <> int.to_string(row.position),
            ),
            rule:,
          )
        }
        case
          list.contains(known, row.creature_id),
          item2.get(tables:, id: Item2Id(row.item_id))
        {
          False, _ ->
            Error(refused(
              "creature "
              <> int.to_string(row.creature_id)
              <> " has no row in the vendor table",
            ))
          True, Error(Nil) ->
            Error(refused(
              "Item2 "
              <> int.to_string(row.item_id)
              <> " has no row in the client's table",
            ))
          True, Ok(_) ->
            item_price.base(tables:, item2_id: Item2Id(row.item_id))
            |> result.map(fn(base) { #(row, base) })
            |> result.map_error(fn(error) {
              refused(item_price.describe(error:))
            })
        }
      }),
    )
  let refusals = list.append(vendor_refusals, item_refusals)
  use <- bool.guard(when: refusals != [], return: Error(refusals))
  Ok(
    Vendors(
      by_creature: dict.from_list(
        list.map(vendors, fn(row) {
          #(
            Creature2Id(row.creature_id),
            Vendor(
              buy_multiplier: row.buy_multiplier,
              sell_multiplier: row.sell_multiplier,
              items: stock_of(priced, row),
            ),
          )
        }),
      ),
    ),
  )
}

/// The creature's items in position order, each at the price its vendor's buy multiplier gives
/// its buy price.
fn stock_of(priced: List(#(ItemRow, Int)), vendor: VendorRow) -> List(Stocked) {
  priced
  |> list.filter(fn(entry) { { entry.0 }.creature_id == vendor.creature_id })
  |> list.sort(fn(left, right) {
    int.compare({ left.0 }.position, { right.0 }.position)
  })
  |> list.map(fn(entry) {
    let #(row, base) = entry
    Stocked(
      position: row.position,
      item_id: Item2Id(row.item_id),
      price: item_price.shown(base:, buy_multiplier: vendor.buy_multiplier),
    )
  })
}

/// Whether the creature is a vendor.
pub fn is_vendor(
  vendors vendors: Vendors,
  creature_id creature_id: Creature2Id,
) -> Bool {
  dict.has_key(vendors.by_creature, creature_id)
}

/// The creature's vendor row and stock, or an error when it is not a vendor.
pub fn get(
  vendors vendors: Vendors,
  creature_id creature_id: Creature2Id,
) -> Result(Vendor, Nil) {
  dict.get(vendors.by_creature, creature_id)
}

/// Every vendor's creature, in id order.
pub fn creatures(vendors vendors: Vendors) -> List(Creature2Id) {
  dict.keys(vendors.by_creature)
  |> list.sort(fn(left, right) {
    let Creature2Id(a) = left
    let Creature2Id(b) = right
    int.compare(a, b)
  })
}
