//// The spell a worn item puts on its wearer, and the spells that are roots of the standing
//// plans.
////
//// ```
//// Item2.itemSpecialId00 ─▶ ItemSpecial.spell4IdOnEquip ─▶ the Spell4 that stands while the item is worn
////        └─ the item must take an equipped slot (`item_property.is_slotted`)
//// ```
////
//// - **An equip spell** is `ItemSpecial.spell4IdOnEquip` of the item's special (the client
////   shows it only in the item's tooltip, so the server is what plays it).
//// - **An item that takes no slot gives none**: a rune, whose family holds no slot, and an
////   item with the proxy flag (`Item2.flags` 0x4000) are never worn, so the spells their
////   specials name are no roots (`item_property.is_slotted`, `CheckItemEquipSlot 0x1403b11b0`).
//// - **A root** is the equip spell of any Item2 row that takes a slot; the plans hold one
////   for each (`genesis_prime/game/spell_plan` `standing_plans`).
//// - **A row the tables lack is an error**, never "not worn": a special row behind a non-zero
////   `itemSpecialId00`, and the Item2Type, ItemCategory or ItemFamily row of an item whose
////   special names an equip spell. `roots` returns it and the plans' load fails with it; the
////   inventory treats the same error as a broken item.

import genesis_prime/game/item_property
import genesis_prime/table/id.{Item2Id, ItemSpecialId}
import genesis_prime/table/item2
import genesis_prime/table/item_special
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The Spell4 id the worn item's special names as its equip spell, or `None` for an item
/// with no special, a special with no equip spell, an item that takes no equipped slot, an
/// Item2 id the table lacks, and an item whose rows cannot be read (the gear lists such an
/// item as unread, and the load's `roots` fails on it).
pub fn of_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Option(Int) {
  case item2.get(tables:, id: Item2Id(item2_id)) {
    Ok(row) -> of_row(tables:, row:) |> result.unwrap(or: None)
    Error(Nil) -> None
  }
}

/// The equip spell of every Item2 row that takes an equipped slot, each once, lowest Spell4
/// id first; the first row of an item the tables cannot read fails it.
pub fn roots(
  tables tables: table_store.Tables,
) -> Result(List(Int), item_property.ItemPropertyError) {
  use spells <- result.map(
    list.try_map(item2.all(tables), fn(row) { of_row(tables:, row:) }),
  )
  spells
  |> option.values
  |> list.unique
  |> list.sort(int.compare)
}

/// The equip spell of an item row. A special row the table lacks behind a non-zero
/// `itemSpecialId00`, and a missing Item2Type, ItemCategory or ItemFamily row of an item
/// whose special names an equip spell, are errors, as they are for the inventory.
fn of_row(
  tables tables: table_store.Tables,
  row row: item2.Item2,
) -> Result(Option(Int), item_property.ItemPropertyError) {
  case row.item_special_id00 {
    0 -> Ok(None)
    special_id ->
      case item_special.get(tables:, id: ItemSpecialId(special_id)) {
        Error(Nil) ->
          Error(item_property.NoRow(table: "ItemSpecial", id: special_id))
        Ok(special) if special.spell4_id_on_equip == 0 -> Ok(None)
        Ok(special) ->
          item_property.is_slotted(tables:, item2_id: row.id)
          |> result.map(fn(slotted) {
            case slotted {
              True -> Some(special.spell4_id_on_equip)
              False -> None
            }
          })
      }
  }
}
