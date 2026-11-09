//// What a player's worn items give: the properties, the item visuals and the weapon,
//// worked out from the items held at location 0 and from nothing else. The connection
//// works the gear out at entry and after each equip, unequip, swap or delete of a
//// worn item, and writes it into its player's `Entered`
//// (genesis_prime/game/world_entry). The module is pure.
////
//// ```
//// held items ─▶ of_items ─▶ Gear ─▶ bases(level) ─▶ unit_properties.rebased ─▶ 0x93a
////                             ├────▶ visuals ──────▶ look.rebased ───────────▶ 0x933
////                             └────▶ weapon ───────▶ the cast's weapon check
//// ```
////
//// - **Only location 0 counts**: an item in a bag or the bank gives nothing
////   (`opcode.0x262.worn_visuals`).
//// - **An item the reader refuses is worn and shown and gives no properties**; it is
////   listed in `unread` with its reason, which the connection logs once.
//// - **Max health** is CreatureLevel's Base Health at the level plus the worn items'
////   (`player.level1_base_health`).
//// - **The gear properties** are 7, 35, 36 and 42, and 41, 175, 176 and 178 from a
////   shield; with no shield worn the four shield properties are their UnitProperty2
////   defaults (`player.level1_gear_properties`, `UnitProperty2.client_value`).

import genesis_prime/game/item_property.{
  type ItemProperties, type ItemPropertyError,
}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/id.{type Item2Id, type UnitProperty2Id}
import genesis_prime/table/loader/store as table_store
import gleam/option.{type Option}

/// What the worn items give: their summed properties, the item visuals of those that
/// are drawn, in slot order, the item held in the primary weapon slot, if any, and each
/// worn item whose properties the reader refuses, with the reason.
pub type Gear {
  Gear(
    properties: ItemProperties,
    visuals: List(ItemVisual),
    weapon: Option(Item2Id),
    unread: List(#(Item2Id, ItemPropertyError)),
  )
}

/// The gear of the items held at location 0 among `items`.
pub fn of_items(
  tables _tables: table_store.Tables,
  items _items: List(HeldItem),
) -> Gear {
  panic as "shape: #586 gear.of_items is not built"
}

/// A player's maximum health at `level` with this gear: the Base Health of
/// CreatureLevel's row of the level plus the gear's, rounded. `Error(Nil)` when the
/// table has no row for the level.
pub fn max_health(
  tables _tables: table_store.Tables,
  gear _gear: Gear,
  level _level: Int,
) -> Result(Int, Nil) {
  panic as "shape: #586 gear.max_health is not built"
}

/// The base of each property the gear sets at `level`: 7, 35, 36 and 42, and the four
/// shield properties, which are their UnitProperty2 defaults when no shield is worn.
/// `Error(Nil)` when the table has no Base Health row for the level.
pub fn bases(
  tables _tables: table_store.Tables,
  gear _gear: Gear,
  level _level: Int,
) -> Result(List(#(UnitProperty2Id, Float)), Nil) {
  panic as "shape: #586 gear.bases is not built"
}
