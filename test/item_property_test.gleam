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

import client_tables
import fixture_tables
import game_connection_support
import genesis_prime/game/item_property
import genesis_prime/table/item2
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}
import unitest
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

/// 5423 holds 8 and has no charges. FillItemInfo (0x140444a27 to 0x140444a45)
/// cuts a bag's size to 1 only when maxStackCount and maxCharges are both above
/// 1; no client row reaches it, so the rows are changed.
pub fn a_bag_that_stacks_and_has_charges_opens_one_slot_test() -> Nil {
  use <- owned_test.run(10_000)
  let bag = fixture_tables.root("Item2", 5423)
  let size = fn(tables) {
    let assert Ok(size) = item_property.bag_size(tables:, item2_id: bag)
      as "the item's rows are in the tables"
    size
  }
  use tables <- fixture_tables.changed(table: "Item2", id: bag, with: [
    #("maxCharges", Integer(2)),
  ])
  assert size(tables) == Some(1)
  use tables <- fixture_tables.changed(table: "Item2", id: bag, with: [
    #("maxCharges", Integer(1)),
  ])
  assert size(tables) == Some(8)
}

/// 11538 sells (its type, category and family flags hold 0x20), 9939's hold no 0x20 (joined
/// 0x10000), 6516 is a Quest Item (Item2Family 24) whose joined flags do hold 0x20 (0x100e4) and
/// 12078 is a proxy, which the client gives the joined flags 0x10004 (`0x1404445d0.proxy`).
pub fn an_item_without_flag_0x20_or_of_the_quest_item_family_is_not_sellable_test() -> Nil {
  use <- owned_test.run(10_000)
  let tables = fixture_tables.shared()
  let sellable = fn(item2_id) {
    let assert Ok(sellable) = item_property.sellable(tables:, item2_id:)
      as "the item's rows are in the tables"
    sellable
  }
  assert sellable(fixture_tables.root("Item2", 11_538))
    as "0x14040d160.sell_cleared: joined flags with 0x20 and a family other than 24 keep the sell price"
  assert !sellable(fixture_tables.root("Item2", 9939))
    as "0x14040d160.sell_cleared: joined flags 0x10000 lack 0x20, so the price is cleared"
  assert !sellable(fixture_tables.root("Item2", 6516))
    as "0x14040d160.sell_cleared: Item2Family 24 (Quest Item) clears the price whatever the flags hold"
  assert !sellable(fixture_tables.root("Item2", 12_078))
    as "0x14040d160.sell_cleared with 0x1404445d0.proxy: a proxy's joined flags 0x10004 lack 0x20"
  assert item_property.sellable(tables:, item2_id: 1_999_999_999)
    == Error(item_property.NoRow(table: "Item2", id: 1_999_999_999))
    as "a missing Item2 row is an error, not a refusal to sell"
}

pub fn the_client_rule_makes_56437_item2_rows_sellable_and_every_bag_among_them_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let ids = list.map(item2.all(tables), fn(row) { row.id })
  let sellable = fn(item2_id) {
    let assert Ok(sellable) = item_property.sellable(tables:, item2_id:)
      as "every Item2 row has its type, category and family rows"
    sellable
  }
  let bags =
    list.filter(ids, fn(item2_id) {
      let assert Ok(size) = item_property.bag_size(tables:, item2_id:)
        as "every Item2 row has its type, category and family rows"
      size != None
    })
  assert list.length(ids) == 72_106
    as "0x14040d160.sell_cleared: the client's Item2 holds 72,106 rows"
  assert list.length(list.filter(ids, sellable)) == 56_437
    as "0x14040d160.sell_cleared: 56,437 of the 72,106 rows pass the rule and 15,669 do not"
  assert list.length(bags) == 142
    as "item.bags_sellable: the client's Item2 holds 142 bag rows"
  assert list.filter(bags, fn(item2_id) { !sellable(item2_id) }) == []
    as "item.bags_sellable: every bag row is sellable (a worn bag is refused by its location, not by this rule)"
}
