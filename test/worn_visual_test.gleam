//// How worn items are drawn (`genesis_prime/shared/worn_visual`): the visuals
//// of a list of items in slot order, and the slot mask the character list gives
//// the client for them. Expected values come from these places.
//// - The Novice sets and what they wear: `novice_tables` (`Item2.novice_set`,
////   `opcode.0x262.worn_visuals`, `Item2.novice_visuals`).
//// - The select screen's draw, `LuaApplyCharacterToActor` 0x140027380: a slot
////   from 1 to 6 or 20 is drawn from the item its mask bit names (bit slot - 1;
////   bit 6 for slot 20), and a clear bit draws nothing.
//// - The rows an edge case needs are changed rows of the committed Item2 rows.

import fixture_tables
import genesis_prime/shared/worn_visual.{
  type Worn, NoDisplaySource, SlotMask, Worn,
}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import novice_tables
import owned_test
import planted_table.{Integer}
import qcheck

/// The Warrior set of faction 167 (CharacterCreation row 466), each the item of
/// the bag index its Item2Type is worn at: chest 81359, legs 81344, shoulder
/// 81381, shield 8534, weapon 81346, feet 81345 and hands 81380
/// (opcode.0x111.equipped_set).
const chest = 81_359

const legs = 81_344

const shoulder = 81_381

const shield = 8534

const weapon = 81_346

const feet = 81_345

const hands = 81_380

/// The slot and display of each drawn visual.
fn slots_and_displays(worn worn: Worn) -> List(#(Int, Int)) {
  list.map(worn.drawn, fn(drawn) {
    #(drawn.visual.slot.value, drawn.visual.display.value)
  })
}

fn worn_of(tables tables: table_store.Tables, items items: List(Int)) -> Worn {
  worn_visual.of_items(tables:, item2_ids: list.map(items, Item2Id))
}

pub fn the_slots_of_worn_items_are_drawn_in_slot_order_and_an_undrawn_item_is_left_out_with_its_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let whole_set = [weapon, shield, hands, chest, feet, legs, shoulder]
  assert slots_and_displays(worn_of(tables:, items: whole_set))
    == novice_tables.worn_visuals(class_id: 1, faction_id: 167)
    as "Item2.novice_visuals: the set held in any order is drawn in slots 1, 2, 4, 5, 6 and 20, in slot order"
  assert worn_of(tables:, items: whole_set).undrawn == []
    as "the Novice items are all dressed or have no display"
  assert worn_of(tables:, items: [shield]) == Worn(drawn: [], undrawn: [])
    as "0x140444130: a shield has no display source, so it is not drawn and is no error"
  assert worn_of(tables:, items: []) == Worn(drawn: [], undrawn: [])
    as "no items, no visuals"
  // A copy of the chest with the flags 0x4000.
  fixture_tables.added(
    table: "Item2",
    copy_of: chest,
    id: 99_001,
    with: [#("flags", Integer(0x4001))],
    body: fn(tables) {
      assert worn_of(tables:, items: [99_001]) == Worn(drawn: [], undrawn: [])
        as "0x140444130: an item whose flags hold 0x4000 is never dressed, and that is no error"
      Nil
    },
  )
  // A copy of the weapon at a power level no ItemDisplaySourceEntry of its source holds.
  fixture_tables.added(
    table: "Item2",
    copy_of: weapon,
    id: 99_002,
    with: [#("powerLevel", Integer(9999))],
    body: fn(tables) {
      let worn = worn_of(tables:, items: [chest, 99_002])
      assert slots_and_displays(worn) == [#(1, 3838)]
        as "the other item is still drawn"
      assert worn.undrawn
        == [
          #(
            Item2Id(99_002),
            NoDisplaySource(
              item2_id: 99_002,
              item_source_id: 75,
              item2_type_id: 51,
              power_level: 9999,
            ),
          ),
        ]
        as "0x140444130: no ItemDisplaySourceEntry of source 75 and type 51 holds power level 9999, so the item is listed undrawn with that reason"
      Nil
    },
  )
}

pub fn the_select_screens_slot_mask_has_a_bit_for_each_worn_armour_and_weapon_slot_and_the_item_in_its_place_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let none = SlotMask(mask: 0, item2_ids: [], dyes: [])
  let seven_dyes = [0, 0, 0, 0, 0, 0, 0]
  let in_place = fn(items) { list.map(items, Item2Id) }
  let rows = [
    #(
      [weapon, shield, hands, chest, feet, legs, shoulder],
      SlotMask(
        mask: 0x7B,
        item2_ids: in_place([chest, legs, 0, shoulder, feet, hands, weapon]),
        dyes: seven_dyes,
      ),
      "the full set: bits 0, 1, 3, 4, 5 and 6, the item of each in its place and 0 where no bit is set (0x140027380)",
    ),
    #(
      [chest],
      SlotMask(
        mask: 0x01,
        item2_ids: in_place([chest, 0, 0, 0, 0, 0, 0]),
        dyes: seven_dyes,
      ),
      "a chest: slot 1 is bit 0",
    ),
    #(
      [weapon],
      SlotMask(
        mask: 0x40,
        item2_ids: in_place([0, 0, 0, 0, 0, 0, weapon]),
        dyes: seven_dyes,
      ),
      "a weapon: slot 20 is bit 6",
    ),
    #([shield], none, "a shield (slot 43) has no mask bit"),
    #([], none, "no items"),
  ]
  list.each(rows, fn(row) {
    let #(items, expected, reason) = row
    assert worn_visual.slot_mask(drawn: worn_of(tables:, items:).drawn)
      == expected
      as reason
  })
  // A copy of the chest in an Item2Type of ItemSlot 47 (a bag), with its own display.
  fixture_tables.added(
    table: "Item2",
    copy_of: chest,
    id: 99_003,
    with: [#("item2TypeId", Integer(134)), #("itemDisplayId", Integer(3838))],
    body: fn(tables) {
      let worn = worn_of(tables:, items: [99_003])
      assert slots_and_displays(worn) == [#(47, 3838)]
        as "the bag is drawn in slot 47 from the list"
      assert worn_visual.slot_mask(drawn: worn.drawn) == none
        as "a worn bag (slot 47) has no mask bit"
      Nil
    },
  )
}

/// The mask bit of a Novice item's bag index: chest 0, legs 1, shoulder 3, feet
/// 4, hands 5 and the weapon 16 are bits 0, 1, 3, 4, 5 and 6; the shield has none
/// (`novice_tables.bag_index_of`, 0x140027380).
fn bit_of(bag_index bag_index: Int) -> Result(Int, Nil) {
  case bag_index {
    0 -> Ok(0)
    1 -> Ok(1)
    3 -> Ok(3)
    4 -> Ok(4)
    5 -> Ok(5)
    16 -> Ok(6)
    _ -> Error(Nil)
  }
}

pub fn a_slot_mask_bit_is_set_only_for_a_slot_with_a_drawn_visual_and_names_the_item_that_gave_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let sets = novice_tables.sets()
  qcheck.given(
    qcheck.tuple2(
      qcheck.bounded_int(from: 0, to: list.length(sets) - 1),
      qcheck.bounded_int(from: 0, to: 127),
    ),
    fn(drawn) {
      let #(set_index, subset) = drawn
      let assert Ok(set) = list.first(list.drop(sets, set_index))
        as "the set index is in range"
      let held =
        list.index_map(novice_tables.equipped_of(set:), fn(pair, index) {
          #(
            pair,
            int.bitwise_and(subset, int.bitwise_shift_left(1, index)) != 0,
          )
        })
        |> list.filter(fn(pair) { pair.1 })
        |> list.map(fn(pair) { pair.0 })
      let worn = worn_of(tables:, items: list.map(held, fn(pair) { pair.0 }))
      let mask = worn_visual.slot_mask(drawn: worn.drawn)
      let expected =
        list.filter_map(held, fn(pair) {
          case bit_of(bag_index: pair.1) {
            Ok(bit) -> Ok(#(bit, pair.0))
            Error(Nil) -> Error(Nil)
          }
        })
      assert mask.mask
        == list.fold(expected, 0, fn(sum, pair) {
          int.bitwise_or(sum, int.bitwise_shift_left(1, pair.0))
        })
      case expected {
        [] -> {
          assert mask.item2_ids == [] && mask.dyes == []
        }
        _ -> {
          assert mask.item2_ids
            == list.map([0, 1, 2, 3, 4, 5, 6], fn(bit) {
              case list.key_find(expected, bit) {
                Ok(item) -> Item2Id(item)
                Error(Nil) -> Item2Id(0)
              }
            })
          assert mask.dyes == [0, 0, 0, 0, 0, 0, 0]
        }
      }
    },
  )
}
