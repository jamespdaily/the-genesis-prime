//// The held items the worn-item tests build, and the deflector they share.
////
//// A test names an item by its Item2 id (read through `fixture_tables.root`, so the id is a
//// root of the committed rows) and where it is held: location 0 is worn, 1 is a bag.

import fixture_tables
import genesis_prime/store.{type HeldItem, HeldItem}
import genesis_prime/table/id.{Item2Id}
import gleam/list
import gleam/option.{None}

/// Item2 91747, the Chua Tighty-Whitey Deflector: Item2Type 53 (ItemSlot 43, ArmorShields,
/// worn in slot 15), requiredLevel 0 and no class, prerequisite or proficiency, so a level 1
/// player may wear it. Its ItemSpecial 9402 names the equip spell 82325, a shield-depleted
/// Proc and no property modifier.
pub const deflector = 91_747

/// The deflector's equip spell.
pub const deflector_spell = 82_325

/// One item held with the guid, at the location and bag index, with no charges or flags.
pub fn held(
  item2_id item2_id: Int,
  item_guid item_guid: Int,
  location location: Int,
  bag_index bag_index: Int,
) -> HeldItem {
  HeldItem(
    item_guid:,
    item2_id: Item2Id(fixture_tables.root(table: "Item2", id: item2_id)),
    location:,
    bag_index:,
    stack_count: 1,
    words: store.ItemWords(
      random_stats: 0,
      charges: 0,
      item_flags: 0,
      expires_at_unix_ms: None,
    ),
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
