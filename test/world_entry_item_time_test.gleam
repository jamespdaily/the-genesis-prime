//// The time left of the items a character holds at world entry (`genesis_prime/game/world_entry`).
//// Expected values come from these places.
//// - `opcode.0x111.time_left`: the client counts a timed item down from the 0x111 that adds it,
////   and nothing else sends the time left, so the entry carries, for each item that runs out,
////   the milliseconds from the entry to its moment, at least 1, and 0 for an item that does not.
//// - The entry's time is the system time `world_entry_support.filetime`; a moment is that time
////   in Unix milliseconds plus what the case adds.
//// - The items are the Novice set of the tests' class 4 and faction 167
////   (`world_entry_support.novice_items`, guids 1 to 7) and the items the cases add: the single
////   and the stackable row of `item_expiry_support`.

import connection_rule_support as support
import fixture_tables
import genesis_prime/store.{type HeldItem}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import item_charge_support
import item_expiry_support
import owned_test
import world_entry_support

/// The Unix milliseconds of the entry.
fn entry_unix_ms() -> Int {
  support.unix_ms_of_filetime(filetime: world_entry_support.filetime)
}

/// The guid, place, count and time left each held item's 0x111 carries at the entry, by guid.
fn sent_times(
  items items: List(HeldItem),
) -> List(#(Int, #(Int, Int), Int, Int)) {
  let character =
    world_entry_support.character(class: 4, faction: 167, level: 1)
  let entry =
    item_charge_support.entry_of(
      tables: fixture_tables.shared(),
      held: list.append(world_entry_support.novice_items(character:), items),
      unset: [],
    )
  world_entry_support.items_added(frames: entry.frames)
  |> list.map(fn(added) {
    let item = added.held_item.item
    #(
      item.item_guid,
      #(item.location, item.bag_index),
      item.stack_count,
      item.time_left_ms,
    )
  })
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.filter(fn(sent) { sent.0 > 7 && sent.0 < 1000 })
}

pub fn the_entry_sends_each_items_time_left_test() -> Nil {
  use <- owned_test.run(10_000)
  let now = entry_unix_ms()
  let items = [
    item_expiry_support.held(
      guid: 21,
      item2: item_expiry_support.single,
      location: 1,
      bag_index: 0,
      count: 1,
      expires_at_unix_ms: Some(now + 40_000),
    ),
    item_expiry_support.held(
      guid: 22,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 1,
      count: 20,
      expires_at_unix_ms: Some(now + 1_728_000_000),
    ),
    item_expiry_support.held(
      guid: 23,
      item2: item_expiry_support.single,
      location: 1,
      bag_index: 2,
      count: 1,
      expires_at_unix_ms: Some(now),
    ),
    item_expiry_support.held(
      guid: 24,
      item2: item_expiry_support.single,
      location: 2,
      bag_index: 0,
      count: 1,
      expires_at_unix_ms: Some(now - 5000),
    ),
    item_expiry_support.held(
      guid: 25,
      item2: item_expiry_support.stackable,
      location: 1,
      bag_index: 3,
      count: 3,
      expires_at_unix_ms: None,
    ),
  ]
  assert sent_times(items:)
    == [
      #(21, #(1, 0), 1, 40_000),
      #(22, #(1, 1), 20, 1_728_000_000),
      #(23, #(1, 2), 1, 1),
      #(24, #(2, 0), 1, 1),
      #(25, #(1, 3), 3, 0),
    ]
    as "each 0x111 carries the time to the item's moment, 1 for a moment that has come, 0 for an item that does not run out, with its guid, place and count as before"
  assert list.all(
    world_entry_support.items_added(
      frames: item_charge_support.entry_of(
        tables: fixture_tables.shared(),
        held: world_entry_support.novice_items(
          character: world_entry_support.character(
            class: 4,
            faction: 167,
            level: 1,
          ),
        ),
        unset: [],
      ).frames,
    ),
    fn(added) { added.held_item.item.time_left_ms == 0 },
  )
    as "the Novice set and the ability bag run out never: their 0x111 carries 0"
}
