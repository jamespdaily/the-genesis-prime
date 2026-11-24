//// The held items the worn-item tests build, and the deflector they share.
////
//// A test names an item by its Item2 id (read through `fixture_tables.root`, so the id is a
//// root of the committed rows) and where it is held: location 0 is worn, 1 is a bag.

import fixture_tables
import genesis_prime/store.{type HeldItem}
import gleam/list
import item_flags_support

/// Item2 91747, the Chua Tighty-Whitey Deflector: Item2Type 53 (ItemSlot 43, ArmorShields,
/// worn in slot 15), requiredLevel 0 and no class, prerequisite or proficiency, so a level 1
/// player may wear it. Its ItemSpecial 9402 names the equip spell 82325, a shield-depleted
/// Proc and no property modifier.
pub const deflector = 91_747

/// The deflector's equip spell.
pub const deflector_spell = 82_325

/// One item held with the guid, at the location and bag index, with no charges or flags; the
/// Item2 id is read as a root of the committed rows.
pub fn held(
  item2_id item2_id: Int,
  item_guid item_guid: Int,
  location location: Int,
  bag_index bag_index: Int,
) -> HeldItem {
  item_flags_support.held_with(
    guid: item_guid,
    item2: fixture_tables.root(table: "Item2", id: item2_id),
    location:,
    bag_index:,
    item_flags: 0,
  )
}

/// Items held as `#(Item2 id, location, bag index)`, with the guids 1 up.
pub fn held_items(items items: List(#(Int, Int, Int))) -> List(HeldItem) {
  list.index_map(items, fn(item, index) {
    let #(item2_id, location, bag_index) = item
    held(item2_id:, item_guid: index + 1, location:, bag_index:)
  })
}

/// The deflector, with the guid 50, at the location and bag index.
pub fn deflector_at(
  location location: Int,
  bag_index bag_index: Int,
) -> HeldItem {
  held(item2_id: deflector, item_guid: 50, location:, bag_index:)
}
