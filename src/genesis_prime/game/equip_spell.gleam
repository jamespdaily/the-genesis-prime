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
/// with no special, a special with no equip spell, an item that takes no equipped slot, and
/// an Item2 id the table lacks.
pub fn of_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Option(Int) {
  case item2.get(tables:, id: Item2Id(item2_id)) {
    Ok(row) -> of_row(tables:, row:)
    Error(Nil) -> None
  }
}

/// The equip spell of every Item2 row that takes an equipped slot, each once, lowest Spell4
/// id first.
pub fn roots(tables tables: table_store.Tables) -> List(Int) {
  item2.all(tables)
  |> list.filter_map(fn(row) { of_row(tables:, row:) |> option.to_result(Nil) })
  |> list.unique
  |> list.sort(int.compare)
}

fn of_row(
  tables tables: table_store.Tables,
  row row: item2.Item2,
) -> Option(Int) {
  let equip =
    item_special.get(tables:, id: ItemSpecialId(row.item_special_id00))
    |> result.map(fn(special) { special.spell4_id_on_equip })
  case equip {
    Ok(spell4_id) if spell4_id != 0 ->
      // Only a missing row of the item's type, category or family is an error, and an item
      // with none is not worn.
      case
        item_property.is_slotted(tables:, item2_id: row.id)
        |> result.unwrap(False)
      {
        True -> Some(spell4_id)
        False -> None
      }
    Ok(_) | Error(Nil) -> None
  }
}
