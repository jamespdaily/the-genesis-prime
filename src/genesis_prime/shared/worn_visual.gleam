//// How a worn item is drawn on its wearer: the model slot and the display the
//// client sets for it. The client draws a unit's armor and weapon only from the
//// item visuals of its 0x262, never from the items it holds, so the server
//// sends one per worn item (`opcode.0x262.worn_visuals`). The character list
//// carries the same visuals and a slot mask over them, since the select screen
//// draws an armour or weapon slot only where its mask bit is set
//// (`opcode.0x117.costume_slots`).
////
//// ```
//// Item2 row ─▶ type ─▶ ItemSlot id ───────────────────────────────▶ slot
////    │                                                                │
////    ├─ flags 0x4000 ─▶ no visual                                     ├─▶ WornVisual
////    ├─ itemDisplayId ≠ 0 ───────────────────────────────────────▶ display
////    └─ itemSourceId, type, power level ─▶ ItemDisplaySourceEntry ─▶ display
//// ```
////
//// - **The slot** is the ItemSlot id of the item's Item2Type (the create screen's
////   own rule, `LuaSetItemsByCreationId` 0x14004adb0).
//// - **The display** is the item's own itemDisplayId when it is not 0; else the
////   itemDisplayId of the first ItemDisplaySourceEntry row of the item's
////   itemSourceId and item2TypeId whose itemMinLevel to itemMaxLevel holds its
////   power level (FindItemDisplaySourceEntry 0x140444130). An item with no
////   source has no display, which is the same as no visual: a shield's.
//// - **An item whose flags hold 0x4000** is never dressed (0x140444130).
//// - **What the loadout refuses:** the client also leaves an item undressed
////   when its type, category and family flags lack 0x400 or its equipped slot
////   flags are 0 (`opcode.0x262.worn_visuals`). The loadout refuses such an item
////   at load: item_property gives it no equipped slot flags (a Novice item has
////   none of its own), so
////   `armor_of` and `weapon_of` fail with `NoEquippedSlot` or `NoWeapon` before
////   a visual is asked for. An item with flags 0x4000 is refused there as well
////   (item_property), so the 0x4000 rule here is the client's, kept for an item
////   outside a Novice set.

import genesis_prime/message/item_visual.{type ItemVisual, ItemVisual}
import genesis_prime/table/id.{
  type Item2Id, type ItemDisplayId, type ItemSlotId, Item2Id, Item2TypeId,
  ItemDisplayId, ItemSlotId,
}
import genesis_prime/table/item2
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_display_source_entry
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The model slot an item is drawn in and the display it is drawn with.
pub type WornVisual {
  WornVisual(slot: ItemSlotId, display: ItemDisplayId)
}

/// Why an item's visual cannot be given.
pub type WornVisualError {
  /// A table the rule reads has no row with this id.
  NoRow(table: String, id: Int)
  /// No ItemDisplaySourceEntry row of the item's source and type holds its
  /// power level.
  NoDisplaySource(
    item2_id: Int,
    item_source_id: Int,
    item2_type_id: Int,
    power_level: Int,
  )
}

/// A sentence that says why, for the load's message.
pub fn describe(error error: WornVisualError) -> String {
  case error {
    NoRow(table:, id:) ->
      "the table " <> table <> " has no row " <> int.to_string(id)
    NoDisplaySource(item2_id:, item_source_id:, item2_type_id:, power_level:) ->
      "the table ItemDisplaySourceEntry has no row of item source "
      <> int.to_string(item_source_id)
      <> " and item type "
      <> int.to_string(item2_type_id)
      <> " for power level "
      <> int.to_string(power_level)
      <> ", which dresses the item "
      <> int.to_string(item2_id)
  }
}

/// The sentence for a worn item that is not drawn, for the log.
pub fn describe_undrawn(
  item2_id item2_id: Item2Id,
  error error: WornVisualError,
) -> String {
  "the worn item "
  <> int.to_string(item2_id.value)
  <> " is not drawn: "
  <> describe(error:)
}

/// Item2.flags 0x4000: an item the client never dresses (0x140444130).
const undressed_flag = 0x4000

/// The visual of a worn item, or `None` for an item that is not drawn: one
/// whose flags hold 0x4000, or one with no display.
pub fn of_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Int,
) -> Result(Option(WornVisual), WornVisualError) {
  use item <- result.try(
    item2.get(tables:, id: Item2Id(item2_id))
    |> result.replace_error(NoRow(table: "Item2", id: item2_id)),
  )
  use type_row <- result.try(
    item2_type.get(tables:, id: Item2TypeId(item.item2_type_id))
    |> result.replace_error(NoRow(table: "Item2Type", id: item.item2_type_id)),
  )
  use display <- result.try(
    case int.bitwise_and(item.flags, undressed_flag) != 0 {
      True -> Ok(None)
      False -> display_of(tables:, item:)
    },
  )
  case display {
    Some(display) -> {
      use _ <- result.try(
        item_display.get(tables:, id: display)
        |> result.replace_error(NoRow(table: "ItemDisplay", id: display.value)),
      )
      Ok(Some(WornVisual(slot: ItemSlotId(type_row.item_slot_id), display:)))
    }
    None -> Ok(None)
  }
}

/// The display of an item that may be dressed: its own, else its source's.
fn display_of(
  tables tables: table_store.Tables,
  item item: item2.Item2,
) -> Result(Option(ItemDisplayId), WornVisualError) {
  case item.item_display_id, item.item_source_id {
    0, 0 -> Ok(None)
    0, source ->
      case
        list.find(item_display_source_entry.all(tables), fn(entry) {
          entry.item_source_id == source
          && entry.item2_type_id == item.item2_type_id
          && entry.item_min_level <= item.power_level
          && item.power_level <= entry.item_max_level
        })
      {
        Ok(entry) ->
          Ok(case entry.item_display_id {
            0 -> None
            display -> Some(ItemDisplayId(display))
          })
        Error(Nil) ->
          Error(NoDisplaySource(
            item2_id: item.id,
            item_source_id: source,
            item2_type_id: item.item2_type_id,
            power_level: item.power_level,
          ))
      }
    display, _ -> Ok(Some(ItemDisplayId(display)))
  }
}

/// A drawn visual and the item that gave it.
pub type Drawn {
  Drawn(item2_id: Item2Id, visual: WornVisual)
}

/// What a list of worn items is drawn as: the visual of each that is drawn, in
/// slot order (items of one slot in the order given), and each item whose
/// visual the tables cannot give, with the reason. An item with no display, and
/// one the client never dresses, is in neither.
pub type Worn {
  Worn(drawn: List(Drawn), undrawn: List(#(Item2Id, WornVisualError)))
}

/// The visuals of worn items, in slot order. One rule for the world, which
/// sends them in 0x262 (`game/gear`), and the character list.
pub fn of_items(
  tables tables: table_store.Tables,
  item2_ids item2_ids: List(Item2Id),
) -> Worn {
  let seen =
    list.map(item2_ids, fn(item2_id) {
      #(item2_id, of_item(tables:, item2_id: item2_id.value))
    })
  let drawn =
    list.filter_map(seen, fn(pair) {
      case pair.1 {
        Ok(Some(visual)) -> Ok(Drawn(item2_id: pair.0, visual:))
        Ok(None) | Error(_) -> Error(Nil)
      }
    })
    |> list.sort(fn(first, second) {
      int.compare(first.visual.slot.value, second.visual.slot.value)
    })
  let undrawn =
    list.filter_map(seen, fn(pair) {
      case pair.1 {
        Error(error) -> Ok(#(pair.0, error))
        Ok(_) -> Error(Nil)
      }
    })
  Worn(drawn:, undrawn:)
}

/// The slot mask, item ids and dyes of the character list's entry
/// (`CharacterListEntry.costume_slot_mask`, `costume_item_ids`, `costume_dyes`).
/// The ids and dyes are empty when the mask is 0 and seven long otherwise, the
/// slots the client reads.
pub type SlotMask {
  SlotMask(mask: Int, item2_ids: List(Item2Id), dyes: List(Int))
}

/// The mask bit the select screen reads for an armour or weapon slot: slots 1 to
/// 6 are bits 0 to 5 and slot 20 is bit 6; any other slot is drawn from the list
/// alone (`LuaApplyCharacterToActor` 0x140027380).
fn mask_bit(slot slot: Int) -> Result(Int, Nil) {
  case slot {
    20 -> Ok(6)
    slot if slot >= 1 && slot <= 6 -> Ok(slot - 1)
    _ -> Error(Nil)
  }
}

/// The slot mask of drawn visuals: a bit for each armour or weapon slot with a
/// visual, and the id of the item that gave it in the bit's place, 0 elsewhere,
/// with a dye of 0 beside each (the dye of a visual is 0 as in `item_visual`). The
/// client draws these slots from the item the bit names, which for an item
/// with no display of its own (`itemDisplayId` 0) falls back to the list's
/// visual (`opcode.0x117.costume_slots`).
pub fn slot_mask(drawn drawn: List(Drawn)) -> SlotMask {
  let bits =
    list.filter_map(drawn, fn(item) {
      case mask_bit(slot: item.visual.slot.value) {
        Ok(bit) -> Ok(#(bit, item.item2_id))
        Error(Nil) -> Error(Nil)
      }
    })
  case bits {
    [] -> SlotMask(mask: 0, item2_ids: [], dyes: [])
    _ ->
      SlotMask(
        mask: list.fold(bits, 0, fn(mask, pair) {
          int.bitwise_or(mask, int.bitwise_shift_left(1, pair.0))
        }),
        item2_ids: list.map([0, 1, 2, 3, 4, 5, 6], fn(bit) {
          case list.key_find(list.reverse(bits), bit) {
            Ok(item2_id) -> item2_id
            Error(Nil) -> Item2Id(0)
          }
        }),
        dyes: [0, 0, 0, 0, 0, 0, 0],
      )
  }
}

/// The item visual of a worn item as 0x262 carries it: colour set 0 and dye 0,
/// which the client turns into colour 0, as the create screen dresses the same
/// items (`opcode.0x262.worn_visuals`).
pub fn item_visual(worn worn: WornVisual) -> ItemVisual {
  ItemVisual(
    slot: worn.slot.value,
    display_id: worn.display.value,
    item_color_set_id: 0,
    dye: 0,
  )
}
