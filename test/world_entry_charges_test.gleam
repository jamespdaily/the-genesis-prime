//// The charges of the items a character holds at world entry (`genesis_prime/game/world_entry`).
//// Expected values come from these places.
//// - `opcode.0x111.charges`: the client keeps the charges of a held item and refuses to use
////   an item whose Item2 row has maxCharges above 0 while it holds none, so every held item
////   needs the charges its row gives it.
//// - A row saved before the charges column holds none recorded (`store.UnsetItem`). Nothing
////   could be spent before the column existed, so such an item still holds everything its row
////   gives it: the row's maxCharges, 0 for a row with none and for a proxy row
////   (`0x1404445d0.proxy`).
//// - The Item2 rows are the client's own (`fixture_tables`): 2509 holds 99 charges and a stack
////   of 1, 14838 stacks to 50 with 1 charge, 12078 is a proxy whose own row holds 1, and
////   12402 holds none.
//// - The 0x111 of an entry still carries charges 0 for every item: the frames change in the
////   step that spends a charge.

import character_support
import equip_requirement_support
import fixture_tables
import genesis_prime/game/inventory
import genesis_prime/message/item_place
import genesis_prime/message/item_split.{ItemSplit}
import genesis_prime/store.{
  AccountId, CharacterId, FillCharges, ItemFill, ItemMade, Placed,
}
import genesis_prime/table/id.{Item2Id}
import gleam/int
import gleam/list
import gleam/order
import item_charge_support
import owned_test
import planted_table.{Integer}
import player_life_support
import quest_turn_in_support as support
import world_entry_support

/// Rows saved before the column get their row's charges, once: each unset item is filled
/// with the maxCharges of its row and listed in the one fill the store is asked, an item that
/// holds charges is left as it is and not listed, a load with no unset item asks nothing, and
/// the frames still carry 0.
pub fn rows_saved_before_the_charges_column_get_their_rows_charges_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let character =
    world_entry_support.character(class: 4, faction: 167, level: 1)
  let novice = world_entry_support.novice_items(character:)
  // Each unset item: its guid, row, place, count and the charges its row gives.
  let unset_rows = [
    #("an unset single row of 99 charges", 21, 2509, 0, 1, 99),
    #("an unset stackable row of 1 charge", 22, 14_838, 1, 3, 1),
    #("an unset proxy row whose own row holds 1", 23, 12_078, 2, 1, 0),
    #(
      "an unset row with no charges, listed so its NULL ends",
      24,
      12_402,
      3,
      1,
      0,
    ),
  ]
  let entry =
    item_charge_support.entry_of(
      tables:,
      held: list.append(novice, [
        item_charge_support.held(
          guid: 25,
          item2: 2509,
          location: 1,
          bag_index: 4,
          count: 1,
          charges: 7,
        ),
      ]),
      unset: list.map(unset_rows, fn(row) {
        item_charge_support.unset(
          guid: row.1,
          item2: row.2,
          location: 1,
          bag_index: row.3,
          count: row.4,
        )
      }),
    )
  assert entry.asked
    == [
      FillCharges(
        account_id: AccountId(7),
        character_id: CharacterId(42),
        session_epoch: character_support.epoch(1),
        fills: list.map(unset_rows, fn(row) {
          ItemFill(item_guid: row.1, charges: row.5)
        }),
      ),
    ]
    as "one fill, listing each unset item with its row's charges and the item that holds 7 not at all"
  list.each(unset_rows, fn(row) {
    let #(why, guid, item2, _, _, charges) = row
    let assert Ok(item) =
      list.find(entry.items, fn(item) { item.item_guid == guid })
      as "the item is held"
    assert #(item.item2_id, item.charges) == #(Item2Id(item2), charges) as why
  })
  let assert Ok(untouched) =
    list.find(entry.items, fn(item) { item.item_guid == 25 })
    as "the item that held charges is held"
  assert untouched.charges == 7 as "an item that holds charges is left as it is"
  let places =
    list.map(entry.items, fn(item) { #(item.location, item.bag_index) })
  assert places
    == list.sort(places, fn(first, second) {
      int.compare(first.0, second.0)
      |> order.break_tie(int.compare(first.1, second.1))
    })
    as "the items stay in location then bag index order"
  let none =
    item_charge_support.entry_of(
      tables:,
      held: list.append(novice, [
        item_charge_support.held(
          guid: 25,
          item2: 2509,
          location: 1,
          bag_index: 4,
          count: 1,
          charges: 7,
        ),
      ]),
      unset: [],
    )
  assert none.asked == [] as "a load with no unset item asks nothing"
  let sent = world_entry_support.items_added(frames: entry.frames)
  assert sent != [] as "the entry sends its items"
  assert list.all(sent, fn(added) { added.held_item.item.charges == 0 })
    as "the entry's 0x111 still carries charges 0 for every item"
}

/// An unset stack is normalized at entry, before any purchase, reward or split can touch
/// it, so what grows or splits from it holds its row's charges: a stack of 3 of 14838 (row
/// maxCharges 1) is filled with 1; a purchase or a reward of 2 grows it to 5 with no stack
/// made holding 0, and a split of 2 makes a stack holding 1.
pub fn a_migrated_stack_grows_and_splits_with_its_rows_charges_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let character =
    world_entry_support.character(class: 4, faction: 167, level: 1)
  let entry =
    item_charge_support.entry_of(
      tables:,
      held: world_entry_support.novice_items(character:),
      unset: [
        item_charge_support.unset(
          guid: 20,
          item2: 14_838,
          location: 1,
          bag_index: 0,
          count: 3,
        ),
      ],
    )
  let assert Ok(stack) =
    list.find(entry.items, fn(item) { item.item_guid == 20 })
    as "the migrated stack is held"
  assert stack.charges == 1 as "the stack is filled with its row's maxCharges"
  // A purchase: the shared placement every buy makes.
  let assert Ok(#(grow, make)) =
    inventory.placed(
      items: entry.items,
      item2_id: Item2Id(14_838),
      size: 16,
      limit: 50,
      wanted: 2,
      charges: 1,
    )
  assert #(
      list.map(grow, fn(growth) {
        #(growth.item_guid, growth.held_count, growth.new_count)
      }),
      make,
    )
    == #([#(20, 3, 5)], [])
    as "a purchase of 2 grows the migrated stack to 5 and makes no stack"
  // A quest reward of 2 of the same row.
  use quest_tables <- support.with_changes(changes: [
    support.receiving(2909),
    #("Quest2Reward", 2369, [
      #("objectId", Integer(14_838)),
      #("objectAmount", Integer(2)),
    ]),
  ])
  let #(turn_in, _) =
    support.asked(
      scene: support.Scene(
        ..support.scene(quest_id: 2909),
        reward_id: 2369,
        items: entry.items,
      ),
      tables: quest_tables,
    )
  let assert Ok(Placed(grow: rewarded_grow, make: rewarded_make, ..)) =
    list.find(turn_in.placed, fn(placed) { placed.item2_id == Item2Id(14_838) })
    as "the reward is placed"
  assert #(list.length(rewarded_grow), rewarded_make) == #(1, [])
    as "a reward of 2 grows the migrated stack and makes no stack"
  // A split of 2.
  let assert Ok(inventory.Asks(moving:)) =
    inventory.take(
      items: entry.items,
      life: player_life_support.alive(),
      tables:,
      wearer: equip_requirement_support.engineer(),
      bag_slots: 0,
      message: inventory.SplitAsked,
      body: split_body(guid: 20, to: #(1, 2), count: 2),
    )
    as "the split passes every check"
  let #(made, _) =
    inventory.answered(
      items: entry.items,
      moving:,
      answer: ItemMade(item_guid: 77),
    )
  let assert Ok(split) = list.find(made, fn(item) { item.item_guid == 77 })
    as "the new stack is held"
  assert split.charges == 1
    as "a split of 2 makes a stack holding the source's 1"
  assert list.all(made, fn(item) {
    item.item2_id != Item2Id(14_838) || item.charges == 1
  })
    as "no stack of the row holds 0"
}

/// The body of a 0x17D that splits `count` of the stack `guid` onto a place.
fn split_body(
  guid guid: Int,
  to to: #(Int, Int),
  count count: Int,
) -> BitArray {
  let assert Ok(body) =
    item_split.encode(ItemSplit(
      item_guid: guid,
      to: item_place.ItemPlace(location: to.0, bag_index: to.1),
      count:,
    ))
    as "a guid, a place and a count fit 0x17D"
  body
}
