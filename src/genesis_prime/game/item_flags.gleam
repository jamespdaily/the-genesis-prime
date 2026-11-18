//// The flags byte of a held item, as the client reads it with the item (0x111's shared
//// item record, 0x567): a held item's bits and the bits a move sets.
////
//// ```
//// a move to a place -> set_by_move(tables, item, to) -> the bits the move adds
//// ```
////
//// - Bit 0 is soulbound: the client binds nothing itself and asks to confirm an equip of
////   a bind-on-equip item that is not soulbound (`0x1403c17d0.equip_confirm`); a row it
////   shows bound whatever the byte holds needs no bit (`0x14056a3f0`).
//// - Bit 3 is no refund (`opcode.0x111.shared_item_unnamed`); no rule here sets it.

import genesis_prime/game/item_property.{type ItemPropertyError}
import genesis_prime/store.{type HeldItem, type ItemPlace}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/int
import gleam/result

/// Bit 0: the item is bound to its owner (`opcode.0x111.shared_item_unnamed`).
const soulbound = 1

/// The location of the worn slots. The client's confirm tests locations 0, 8 and 9
/// (`0x1403c17d0.equip_confirm`); the move check refuses a move to any place from 3 to 99,
/// so only 0 is reached.
const equipped_location = 0

/// Whether the byte holds the soulbound bit.
fn is_soulbound(item_flags item_flags: Int) -> Bool {
  int.bitwise_and(item_flags, soulbound) != 0
}

/// The bits a move of the item to `to` adds to its flags byte, none it already holds: the
/// soulbound bit when the place is a worn slot and the item's row binds on equip, as the
/// client's move sender asks for it (`0x1403c17d0.equip_confirm`); 0 for any other place
/// and any other row. Only a missing row is an error.
pub fn set_by_move(
  tables tables: table_store.Tables,
  item item: HeldItem,
  to to: ItemPlace,
) -> Result(Int, ItemPropertyError) {
  use <- bool.guard(when: to.location != equipped_location, return: Ok(0))
  use binds <- result.map(item_property.binds_on_equip(
    tables:,
    item2_id: item.item2_id.value,
  ))
  case binds && !is_soulbound(item_flags: item.item_flags) {
    True -> soulbound
    False -> 0
  }
}
