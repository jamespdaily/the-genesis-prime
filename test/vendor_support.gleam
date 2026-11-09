//// Vendors for a test to stock a creature with: the content load's own `vendor.select`
//// over the client's committed rows, so a creature and an item a test names are rows the
//// client has.

import character_tables
import genesis_prime/game/vendor.{type Vendors, ItemRow, VendorRow}
import gleam/list

/// The Item2 ids a test stocks: the first three of Supplier Ingavak's list, rows of the
/// committed Item2 table.
pub const items = [12_078, 14_838, 20_791]

/// The 22 Item2 ids Supplier Ingavak (Creature2 28739) sells, in the order of his
/// Jabbithole page, all rows of the committed Item2 table.
pub const ingavaks_items = [
  12_078, 14_838, 20_791, 13_176, 13_185, 13_194, 13_188, 12_044, 13_191, 13_179,
  13_151, 13_154, 13_166, 27_874, 27_873, 27_876, 13_157, 13_163, 27_875, 13_169,
  13_148, 13_160,
]

/// The vendors of these creatures, each selling `items` at positions 1, 2 and 3, with
/// the multipliers the content migration gives every vendor, 1.0.
pub fn stocking(creature_ids creature_ids: List(Int)) -> Vendors {
  stocking_items(creature_ids:, items:)
}

/// The vendors of these creatures, each selling `items` from position 1.
pub fn stocking_items(
  creature_ids creature_ids: List(Int),
  items items: List(Int),
) -> Vendors {
  let rows = list.map(creature_ids, fn(id) { VendorRow(id, 1.0, 1.0) })
  let stock =
    list.flat_map(creature_ids, fn(id) {
      list.index_map(items, fn(item, index) { ItemRow(id, index + 1, item) })
    })
  let assert Ok(vendors) =
    vendor.select(
      vendors: rows,
      items: stock,
      tables: character_tables.shared(),
    )
    as "the creatures and items of the support are rows of the client's committed tables"
  vendors
}
