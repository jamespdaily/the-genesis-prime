//// Shared scenes of the item flags tests: the tables with one Item2 row's bind columns
//// changed, items held with their flags byte, and the rule's output for a move. The rows
//// are the client's own (`fixture_tables`): the Novice chest piece of the Engineer of the
//// tests is the wearable row whose bindFlags the equip tests change, and Item2 74201 is the
//// row GameFormula 1214 names for a proxy item, holding bindFlags 8 (`0x1404445d0.proxy`).

import equip_requirement_support
import fixture_tables
import game_connection_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/inventory.{type Effect, type Moving, type Taken, Send}
import genesis_prime/message/item_move
import genesis_prime/message/item_place
import genesis_prime/store.{type HeldItem, HeldItem}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option, None, Some}
import planted_table.{Integer}
import player_life_support
import world_entry_support

/// Item2.bindFlags bit 4: bind on equip. Bit 3 (8) is bind on pickup.
pub const bind_on_equip = 16

pub const bind_on_pickup = 8

/// Item2.flags 0x4000: a proxy row, whose bindFlags the client takes from Item2 74201.
pub const proxy_flags = 0x4000

/// Runs the body on the tables with the row's bindFlags changed, and its flags too when they
/// are given (`None` leaves the row's own).
pub fn with_bind_flags(
  item2_id item2_id: Int,
  bind_flags bind_flags: Int,
  flags flags: Option(Int),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let changes = case flags {
    Some(flags) -> [#("flags", Integer(flags))]
    None -> []
  }
  fixture_tables.changed(
    table: "Item2",
    id: item2_id,
    with: [#("bindFlags", Integer(bind_flags)), ..changes],
    body:,
  )
}

/// The Item2 id of the chest piece the Engineer of the tests wears from the start: a wearable
/// row for the chest slot, bag index 0.
pub fn chest() -> Int {
  let assert [chest, ..] =
    world_entry_support.novice_items(
      character: game_connection_support.world_character(),
    )
    as "the Engineer's set has its chest piece first"
  assert chest.bag_index == 0
    as "the chest slot is bag index 0, the lowest bit of its slot flags"
  chest.item2_id.value
}

/// An item held, with its flags byte.
pub fn held_with(
  guid guid: Int,
  item2 item2: Int,
  location location: Int,
  bag_index bag_index: Int,
  item_flags item_flags: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2),
    location:,
    bag_index:,
    stack_count: 1,
    random_stats: 0,
    charges: 0,
    item_flags:,
  )
}

/// The rule's answer to a 0x182 of the Engineer of the tests, alive and out of combat.
pub fn take(
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Result(Taken, inventory.Refusal) {
  let assert Ok(body) =
    item_move.encode(item_move.ItemMove(
      from: item_place.ItemPlace(location: from.0, bag_index: from.1),
      to: item_place.ItemPlace(location: to.0, bag_index: to.1),
    ))
    as "two places of 9 and 32 bits fit the message"
  inventory.take(
    items:,
    life: player_life_support.alive(),
    tables:,
    wearer: equip_requirement_support.engineer(),
    bag_slots: 0,
    message: inventory.MoveAsked,
    body:,
  )
}

/// The move the rule asks the store for, which it must have accepted.
pub fn asking(
  items items: List(HeldItem),
  tables tables: table_store.Tables,
  from from: #(Int, Int),
  to to: #(Int, Int),
) -> Moving {
  let assert Ok(inventory.Asks(moving:)) = take(items:, tables:, from:, to:)
    as "the move passes every check, so the store is asked"
  moving
}

/// The moves of an accepted move or swap.
pub fn moves_of(moving: Moving) -> List(store.ItemMove) {
  let assert inventory.Moved(moves:, ..) = moving.change
    as "a 0x182 onto an empty slot or a different item is saved as moves"
  moves
}

/// The frames the effects write.
pub fn sent(effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Send(frame:) -> Ok(frame)
      inventory.Log(..) -> Error(Nil)
    }
  })
}

/// The message ids of the frames the effects write, in order.
pub fn frame_ids(effects: List(Effect)) -> List(Int) {
  list.map(sent(effects), fn(frame) { frame.message_id })
}

/// The flags byte of the held item of the guid.
pub fn flags_of(items items: List(HeldItem), guid guid: Int) -> Int {
  let assert Ok(item) = list.find(items, fn(item) { item.item_guid == guid })
    as "the item is held"
  item.item_flags
}
