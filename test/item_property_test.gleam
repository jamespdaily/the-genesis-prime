//// What an item's own rows say of a bag (`genesis_prime/game/item_property`).
//// Expected values come from these places.
//// - `Item2.bags` and `0x1404445d0.proxy`: a bag is an item whose joined flags
////   (type, category and family) hold 0x100, and it opens Item2.maxStackCount
////   inventory slots; the client gives an item whose Item2.flags hold 0x4000 the
////   joined flags 0x10004 and the equipped slot flags 0, so such a proxy is no
////   bag.
//// - The Item2 rows are the client's own, roots of the fixture: 4753 holds 4
////   and has equipped slot flags 0x7FFE0000 (bag indexes 17 to 30), 5423 holds 8
////   (it needs level 18), 4763 is a proxy whose row holds 4 as maxStackCount, and
////   the Novice chest piece is armor.

import fixture_tables
import game_connection_support
import genesis_prime/game/item_property
import gleam/option.{None, Some}
import owned_test
import world_entry_support

pub fn a_bag_is_a_non_proxy_item_whose_joined_flags_hold_0x100_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let size = fn(item2_id) {
    let assert Ok(size) = item_property.bag_size(tables:, item2_id:)
      as "the item's rows are in the tables"
    size
  }
  assert size(fixture_tables.root("Item2", 4753)) == Some(4)
  assert size(fixture_tables.root("Item2", 5423)) == Some(8)
  let assert [chest, ..] =
    world_entry_support.novice_items(
      character: game_connection_support.world_character(),
    )
    as "the Engineer's set has its chest piece first"
  assert size(chest.item2_id.value) == None
  // The proxy row's own flags say 0x100 through its maxStackCount of 4, and the
  // client's proxy rule drops it.
  let proxy = fixture_tables.root("Item2", 4763)
  assert size(proxy) == None
  let assert Ok(proxy_slots) =
    item_property.equipped_slot_flags(tables:, item2_id: proxy)
  assert proxy_slots == 0
  let assert Ok(bag_slots) =
    item_property.equipped_slot_flags(
      tables:,
      item2_id: fixture_tables.root("Item2", 4753),
    )
  assert bag_slots == 0x7FFE0000
}
