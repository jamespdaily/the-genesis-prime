//// The flags byte of the items a character holds at world entry (`genesis_prime/game/world_entry`).
//// Expected values come from these places.
//// - `opcode.0x111.shared_item_unnamed`: the client keeps the flags byte of each held item
////   (bit 0 soulbound) from the 0x111 that adds it, and nothing else sends it at entry, so
////   the entry carries the byte the store holds for every item.
//// - A row saved before the charges column holds none recorded (`store.UnsetItem`); it still
////   carries its flags byte once the charges are filled.
//// - The items are the Novice set of the tests' class 4 and faction 167
////   (`world_entry_support.novice_items`, guids 1 to 7), each at the bag index of its slot, and
////   the items the cases add.

import fixture_tables
import genesis_prime/store.{HeldItem}
import gleam/int
import gleam/list
import item_charge_support
import item_flags_support
import owned_test
import world_entry_support

/// The flags byte each item of the entry's 0x111 carries, by guid, sorted by guid.
fn sent_flags(entry: item_charge_support.Entry) -> List(#(Int, Int)) {
  world_entry_support.items_added(frames: entry.frames)
  |> list.map(fn(added) {
    #(added.held_item.item.item_guid, added.held_item.item.item_flags)
  })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

/// The entry sends the byte each held item holds: a worn soulbound item, a worn bind-on-pickup
/// item holding none, a bag item that binds on equip holding none, a bag item holding the
/// bit, an item saved before the charges column holding the bit (sent after the fill), and
/// the ability bag's items, which hold none.
pub fn the_entry_sends_each_held_items_flags_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let character =
    world_entry_support.character(class: 4, faction: 167, level: 1)
  let novice =
    list.map(world_entry_support.novice_items(character:), fn(item) {
      case item.item_guid {
        1 -> HeldItem(..item, item_flags: 1)
        _ -> item
      }
    })
  let bag_items = [
    item_flags_support.held_with(
      guid: 21,
      item2: 4753,
      location: 1,
      bag_index: 0,
      item_flags: 0,
    ),
    item_flags_support.held_with(
      guid: 22,
      item2: 5423,
      location: 1,
      bag_index: 1,
      item_flags: 1,
    ),
  ]
  let entry =
    item_charge_support.entry_of(
      tables:,
      held: list.append(novice, bag_items),
      unset: [
        store.UnsetItem(
          ..item_charge_support.unset(
            guid: 23,
            item2: 4753,
            location: 1,
            bag_index: 2,
            count: 1,
          ),
          item_flags: 1,
        ),
      ],
    )
  let sent = sent_flags(entry)
  let expected = [
    #(1, 1),
    #(2, 0),
    #(3, 0),
    #(4, 0),
    #(5, 0),
    #(6, 0),
    #(7, 0),
    #(21, 0),
    #(22, 1),
    #(23, 1),
  ]
  assert list.filter(sent, fn(pair) { pair.0 <= 23 }) == expected
    as "each held item's 0x111 carries the byte it holds, the unset one's too"
  assert list.all(sent, fn(pair) { pair.0 <= 23 || pair.1 == 0 })
    as "an ability at location 4, which no row stores, carries 0"
}
