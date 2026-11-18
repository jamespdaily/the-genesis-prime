//// Shared scenes of the item charge tests: the tables with one Item2 row's charge columns
//// changed, items held with their charges (or with none recorded), and the world-entry
//// rule's output for a load. The rows are the client's own (`fixture_tables`): Item2 2509
//// holds maxCharges 99 and a stack of 1, 12402 holds none, 1039 stacks to 20, 14838 to 50
//// and 20791 to 99, and 74201 is the row GameFormula 1214 names for a proxy item, with
//// maxCharges 0 (`0x1404445d0.proxy`).

import fixture_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/world_entry
import genesis_prime/store.{
  type HeldItem, type UnsetItem, type WorldRequest, HeldItem, UnsetItem,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/option.{type Option, None, Some}
import place_support
import planted_table.{Integer}
import world_entry_support

/// The flags of an Item2 row that make it a proxy item (`0x1404445d0.proxy`).
pub const proxy_flags = 0x4000

/// Runs the body on the tables with the row's maxCharges changed, and its flags and
/// maxStackCount too when they are given (`None` leaves the row's own).
pub fn tables_with(
  item2_id item2_id: Int,
  max_charges max_charges: Int,
  flags flags: Option(Int),
  max_stack_count max_stack_count: Option(Int),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let changes =
    list.flatten([
      [#("maxCharges", Integer(max_charges))],
      case flags {
        Some(flags) -> [#("flags", Integer(flags))]
        None -> []
      },
      case max_stack_count {
        Some(count) -> [#("maxStackCount", Integer(count))]
        None -> []
      },
    ])
  fixture_tables.changed(table: "Item2", id: item2_id, with: changes, body:)
}

/// An item held, with the charges it has left.
pub fn held(
  guid guid: Int,
  item2 item2: Int,
  location location: Int,
  bag_index bag_index: Int,
  count count: Int,
  charges charges: Int,
) -> HeldItem {
  HeldItem(
    item_guid: guid,
    item2_id: Item2Id(item2),
    location:,
    bag_index:,
    stack_count: count,
    random_stats: 0,
    charges:,
  )
}

/// An item the database holds with no charges recorded (a row saved before the column).
pub fn unset(
  guid guid: Int,
  item2 item2: Int,
  location location: Int,
  bag_index bag_index: Int,
  count count: Int,
) -> UnsetItem {
  UnsetItem(
    item_guid: guid,
    item2_id: Item2Id(item2),
    location:,
    bag_index:,
    stack_count: count,
    random_stats: 0,
  )
}

/// What the world-entry rule does with a load: the store requests it asked (none, or
/// the fill), the items the player enters with, and the 0x111 frames of the entry.
pub type Entry {
  Entry(asked: List(WorldRequest), items: List(HeldItem), frames: List(Frame))
}

/// The entry of a character on these tables whose load holds the items `held` (with their
/// charges) and `unset` (with none recorded): the store answers a fill it is asked with
/// `ItemsSaved` and the map takes the player.
pub fn entry_of(
  tables tables: table_store.Tables,
  held held: List(HeldItem),
  unset unset: List(UnsetItem),
) -> Entry {
  let character =
    world_entry_support.character(class: 4, faction: 167, level: 1)
  let #(_, loaded) =
    world_entry_support.loaded_with_unset(tables:, character:, held:, unset:)
  let #(asked, state) = case loaded {
    world_entry.Join(state:, ..) -> #([], state)
    world_entry.Fill(state: filling, effects:) -> #(
      list.filter_map(effects, requested),
      world_entry_support.filled(state: filling, tables:),
    )
    world_entry.Refused(..) | world_entry.Fault(..) ->
      panic as "the load is entered or filled"
  }
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.0,
      y: -853.0,
      z: -560.0,
    )
  let assert world_entry.InTheWorld(entered:, effects:) =
    world_entry_support.joined_state(
      state:,
      tables:,
      character:,
      place:,
      now: world_entry_support.now(),
    )
    as "the map takes the player"
  Entry(
    asked:,
    items: entered.items,
    frames: world_entry_support.frames_of(effects:),
  )
}

fn requested(effect: world_entry.Effect) -> Result(WorldRequest, Nil) {
  case effect {
    world_entry.AskStore(request:) -> Ok(request)
    world_entry.Send(..)
    | world_entry.AskMap(..)
    | world_entry.WatchMap(..)
    | world_entry.Life(..)
    | world_entry.StartPassive(..)
    | world_entry.Warn(..) -> Error(Nil)
  }
}
