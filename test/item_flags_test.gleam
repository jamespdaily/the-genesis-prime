//// The bits a move adds to a held item's flags byte (`genesis_prime/game/item_flags`).
//// Expected values come from these places.
//// - `0x1403c17d0.equip_confirm`: the client's move sender asks to confirm an equip when the
////   destination is a worn slot, the item's row binds on equip and the item is not soulbound
////   (bit 0 of its flags byte), and sends the move only after; the client never sets the bit.
//// - `0x14056a3f0`: IsSoulbound, the item's flags bit 0 for a bindable row.
//// - `opcode.0x111.shared_item_unnamed`: bit 3 of the byte is no refund.
//// - The wearable row is the Novice chest piece of the Engineer of the tests, its bindFlags
////   changed to the case's.

import fixture_tables
import genesis_prime/game/item_flags
import genesis_prime/game/item_property
import genesis_prime/store.{ItemPlace}
import gleam/list
import gleam/option.{None}
import item_flags_support
import owned_test

const worn = ItemPlace(location: 0, bag_index: 0)

const bag = ItemPlace(location: 1, bag_index: 3)

const bank = ItemPlace(location: 2, bag_index: 0)

pub fn a_move_sets_the_soulbound_bit_only_onto_a_worn_place_of_a_bind_on_equip_item_test() -> Nil {
  use <- owned_test.run(20_000)
  let row = item_flags_support.chest()
  // The row's bindFlags, the byte the item holds, where it goes, and the bits the move adds.
  let cases = [
    #("bind on equip, unbound, to a worn slot", 16, 0, worn, Ok(1)),
    #("bind on equip, unbound, to the inventory", 16, 0, bag, Ok(0)),
    #("bind on equip, unbound, to the bank", 16, 0, bank, Ok(0)),
    #(
      "bind on equip, soulbound, to a worn slot: the bit is held",
      16,
      1,
      worn,
      Ok(0),
    ),
    #("bind on equip, soulbound, to the inventory", 16, 1, bag, Ok(0)),
    #("bind on pickup, unbound, to a worn slot", 8, 0, worn, Ok(0)),
    #("no bind flags, unbound, to a worn slot", 0, 0, worn, Ok(0)),
    #(
      "bind on equip holding only no refund: the missing bit",
      16,
      8,
      worn,
      Ok(1),
    ),
  ]
  list.each(cases, fn(case_) {
    let #(why, bind_flags, held, to, expected) = case_
    use tables <- item_flags_support.with_bind_flags(
      item2_id: row,
      bind_flags:,
      flags: None,
    )
    let item =
      item_flags_support.held_with(
        guid: 1,
        item2: row,
        location: 1,
        bag_index: 0,
        item_flags: held,
      )
    assert item_flags.set_by_move(tables:, item:, to:) == expected as why
  })
  let missing =
    item_flags_support.held_with(
      guid: 1,
      item2: 999_999_999,
      location: 1,
      bag_index: 0,
      item_flags: 0,
    )
  assert item_flags.set_by_move(
      tables: fixture_tables.shared(),
      item: missing,
      to: worn,
    )
    == Error(item_property.NoRow(table: "Item2", id: 999_999_999))
    as "a row the tables lack is an error"
}
