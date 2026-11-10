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
//// - **A second shield gives nothing**: its properties would share the first's, so it is
////   listed in `unread` as `TwoShields`; the client's move check lets one shield be worn.
//// - **An item with no display is not drawn**, and neither is one whose display or
////   display source the tables lack a row for; the latter is listed in `undrawn` with
////   its reason, which the connection logs once (`worn_visual`).
//// - **Max health** is CreatureLevel's Base Health at the level plus the worn items'
////   (`player.level1_base_health`).
//// - **The gear properties** are 7, 35, 36 and 42, and 41, 175, 176 and 178 from a
////   shield; with no shield worn the four shield properties are their UnitProperty2
////   defaults (`player.level1_gear_properties`, `UnitProperty2.client_value`). Every
////   other property an item's budget may give is its default plus the worn items'
////   budget values, so taking an item off returns it to the default.

import genesis_prime/game/item_property.{
  type ItemProperties, type ItemPropertyError, Shield,
}
import genesis_prime/game/unit_properties
import genesis_prime/game/worn_visual.{type WornVisualError}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/creature_level
import genesis_prime/table/id.{
  type Item2Id, type UnitProperty2Id, CreatureLevelId, UnitProperty2Id,
}
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The location of the items a player wears.
const worn_location = 0

/// The bag index of the primary weapon slot, WeaponPrimary, bit 16: an item is moved
/// there only when its equipped slot flags hold the weapon bit
/// (`item_property.is_weapon`, `genesis_prime/game/equip_requirement`), so the item
/// held there is the weapon.
const weapon_bag_index = 16

/// What the worn items give: their summed properties, the item visuals of those that
/// are drawn, in slot order, the item held in the primary weapon slot, if any, and each
/// worn item whose properties the reader refuses, with the reason, and each worn item
/// whose visual the tables cannot give, with the reason.
pub type Gear {
  Gear(
    properties: ItemProperties,
    visuals: List(ItemVisual),
    weapon: Option(Item2Id),
    unread: List(#(Item2Id, ItemPropertyError)),
    undrawn: List(#(Item2Id, WornVisualError)),
  )
}

/// The gear of the items held at location 0 among `items`.
pub fn of_items(
  tables tables: table_store.Tables,
  items items: List(HeldItem),
) -> Gear {
  let worn =
    list.filter(items, fn(item) { item.location == worn_location })
    |> list.sort(fn(first, second) {
      int.compare(first.bag_index, second.bag_index)
    })
  let read =
    list.map(worn, fn(item) {
      #(
        item,
        item_property.of_item(
          tables:,
          item2_id: item.item2_id.value,
          random_stats: item.random_stats,
        ),
      )
    })
  let #(given, unread) = keep_one_shield(read:)
  let assert Ok(properties) = item_property.sum(items: given)
    as "at most one shield is kept, so the items sum"
  let seen =
    list.map(worn, fn(item) {
      #(item, worn_visual.of_item(tables:, item2_id: item.item2_id.value))
    })
  let visuals =
    list.filter_map(seen, fn(pair) {
      case pair.1 {
        Ok(Some(visual)) -> Ok(visual)
        Ok(None) | Error(_) -> Error(Nil)
      }
    })
    |> list.sort(fn(first, second) {
      int.compare(first.slot.value, second.slot.value)
    })
    |> list.map(worn_visual.item_visual)
  let undrawn =
    list.filter_map(seen, fn(pair) {
      case pair.1 {
        Error(error) -> Ok(#({ pair.0 }.item2_id, error))
        Ok(_) -> Error(Nil)
      }
    })
  let weapon =
    list.find(worn, fn(item) { item.bag_index == weapon_bag_index })
    |> result.map(fn(item) { item.item2_id })
    |> option.from_result
  Gear(properties:, visuals:, weapon:, unread:, undrawn:)
}

/// What each worn item gives, and each that gives nothing with its reason: an item the
/// reader refuses, and a second shield, whose properties would share the first's.
fn keep_one_shield(
  read read: List(#(HeldItem, Result(ItemProperties, ItemPropertyError))),
) -> #(List(ItemProperties), List(#(Item2Id, ItemPropertyError))) {
  let #(given, unread, _) =
    list.fold(read, #([], [], False), fn(so_far, pair) {
      let #(given, unread, has_shield) = so_far
      let #(item, result) = pair
      case result {
        Error(error) -> #(
          given,
          [#(item.item2_id, error), ..unread],
          has_shield,
        )
        Ok(properties) ->
          case properties.shield, has_shield {
            Some(_), True -> #(
              given,
              [#(item.item2_id, item_property.TwoShields), ..unread],
              has_shield,
            )
            Some(_), False -> #([properties, ..given], unread, True)
            None, _ -> #([properties, ..given], unread, has_shield)
          }
      }
    })
  #(list.reverse(given), list.reverse(unread))
}

/// Why a player's maximum health cannot be worked out.
pub type HealthError {
  /// CreatureLevel has no row for the level.
  NoCreatureLevel(level: Int)
}

/// The text that tells why, for the log.
pub fn describe(error error: HealthError) -> String {
  let NoCreatureLevel(level:) = error
  "CreatureLevel has no row for level "
  <> int.to_string(level)
  <> ", so the player's maximum health is unknown"
}

/// A player's maximum health at `level` with this gear: the Base Health of
/// CreatureLevel's row of the level plus the gear's, rounded. `NoCreatureLevel` when the
/// table has no row for the level.
pub fn max_health(
  tables tables: table_store.Tables,
  gear gear: Gear,
  level level: Int,
) -> Result(Int, HealthError) {
  creature_level.get(tables:, id: CreatureLevelId(level))
  |> result.map(fn(row) {
    float.round(row.unit_property_value07 +. gear.properties.base_health)
  })
  |> result.replace_error(NoCreatureLevel(level:))
}

/// The base of each property the gear sets at `level`: 7, 35, 36 and 42, and the four
/// shield properties, which are their UnitProperty2 defaults when no shield is worn,
/// then each property an item's budget may give (`item_property.budget_properties`), in
/// id order, at its default plus what the worn items give.
/// `NoCreatureLevel` when the table has no Base Health row for the level.
pub fn bases(
  tables tables: table_store.Tables,
  gear gear: Gear,
  level level: Int,
) -> Result(List(#(UnitProperty2Id, Float)), HealthError) {
  use health <- result.map(max_health(tables:, gear:, level:))
  let defaults = unit_properties.defaults(tables:)
  let properties = gear.properties
  let #(capacity, mitigation, regen, reboot) = case properties.shield {
    Some(Shield(capacity_max:, mitigation_max:, regen_percent:, reboot_time_ms:)) -> #(
      capacity_max,
      mitigation_max,
      regen_percent,
      int.to_float(reboot_time_ms),
    )
    None -> #(
      default_of(defaults:, id: unit_properties.shield_capacity_max),
      default_of(defaults:, id: unit_properties.shield_mitigation_max),
      default_of(defaults:, id: unit_properties.shield_regen_percent),
      default_of(defaults:, id: unit_properties.shield_reboot_time),
    )
  }
  let fixed =
    [
      #(7, int.to_float(health)),
      #(35, properties.assault_rating),
      #(36, properties.support_rating),
      #(41, capacity),
      #(42, properties.armor),
      #(175, mitigation),
      #(176, regen),
      #(178, reboot),
    ]
    |> list.map(fn(pair) { #(UnitProperty2Id(pair.0), pair.1) })
  let budget =
    list.map(item_property.budget_properties(tables:), fn(property_id) {
      #(
        property_id,
        default_of(defaults:, id: property_id)
          +. result.unwrap(dict.get(properties.budget, property_id), 0.0),
      )
    })
  list.append(fixed, budget)
}

/// The worn shield's capacity, which is stat 20 of the player's unit when it is created:
/// none with no shield worn (`player.level1_gear_properties`).
pub fn shield_capacity(gear gear: Gear) -> Option(Int) {
  option.map(gear.properties.shield, fn(shield) {
    float.round(shield.capacity_max)
  })
}

/// One warning for each worn item `gear` lists unread or undrawn that `known`, the gear
/// the player wore before, does not list: the item and why it gives no properties or no
/// drawing, and the open issue that closes the gap when the item is unread for one.
/// `None` at entry, where nothing is known yet.
pub fn warnings(gear gear: Gear, known known: Option(Gear)) -> List(String) {
  let #(known_unread, known_undrawn) = case known {
    Some(before) -> #(before.unread, before.undrawn)
    None -> #([], [])
  }
  let unread =
    new_items(items: gear.unread, known: known_unread)
    |> list.map(fn(unread) {
      let #(item2_id, error) = unread
      "the worn item "
      <> int.to_string(item2_id.value)
      <> " gives no properties: "
      <> item_property.describe(error:)
      <> case error {
        item_property.Unread(gap:, ..) ->
          case item_property.gap_issue(gap:) {
            Some(issue) -> " (open issue " <> int.to_string(issue) <> ")"
            None -> ""
          }
        item_property.TwoShields
        | item_property.NoRow(..)
        | item_property.Refused(..)
        | item_property.RandomStatsRefused(..)
        | item_property.NoCurveValue(..) -> ""
      }
    })
  let undrawn =
    new_items(items: gear.undrawn, known: known_undrawn)
    |> list.map(fn(undrawn) {
      let #(item2_id, error) = undrawn
      "the worn item "
      <> int.to_string(item2_id.value)
      <> " is not drawn: "
      <> worn_visual.describe(error:)
    })
  list.append(unread, undrawn)
}

/// The items of `items` that `known` does not list.
fn new_items(
  items items: List(#(Item2Id, reason)),
  known known: List(#(Item2Id, reason)),
) -> List(#(Item2Id, reason)) {
  let known_ids = list.map(known, fn(item) { { item.0 }.value })
  list.filter(items, fn(item) { !list.contains(known_ids, { item.0 }.value) })
}

/// The UnitProperty2 defaultValue of a property the player's rules read; the load
/// refuses tables without its row (genesis_prime/game/unit_properties).
fn default_of(
  defaults defaults: List(#(UnitProperty2Id, Float)),
  id id: UnitProperty2Id,
) -> Float {
  let assert Ok(default) = list.key_find(defaults, id)
    as "the load checks that UnitProperty2 has the shield properties' rows"
  default
}
