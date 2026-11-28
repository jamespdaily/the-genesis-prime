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
//// - **The equip spells** are those the worn items' specials name, each with its item, in the
////   order the items are worn (bag index), an exact repeat listed once. No other rule decides
////   between items that name one spell: the 19 spells several items name are each named by
////   items of one ItemSlot (Item2Type 53 is ItemSlot 43; types 3, 10 and 17 ItemSlot 3; types
////   45, 46, 48, 51, 79 and 204 ItemSlot 20), so two worn items never name one spell at once;
////   were two worn, each would stand as a cast of its own, at its own level. A second shield's
////   spell is listed beside its first's, though its properties are not given; the client's move
////   check lets one shield be worn, so no worn set holds two.
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
////   budget values, so taking an item off returns it to the default. BaseFocusPool (5)
////   is one of them, with the class's own base pool added (`bases`), so a healer's
////   maximum Focus is that pool plus what its items give.
//// - **Base combat properties:** the 26 of CreatureLevel row 101 at every level and with any gear
////   (`player_combat_bases`), the server's guess (`player.base_combat_properties`).

import genesis_prime/gap
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/shared/equip_spell
import genesis_prime/shared/item_property.{
  type ItemProperties, type ItemPropertyError, Shield,
}
import genesis_prime/shared/unit_properties
import genesis_prime/shared/worn_visual.{type WornVisualError}
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/creature_level
import genesis_prime/table/id.{
  type Item2Id, type UnitProperty2Id, CreatureLevelId, UnitProperty2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_columns
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
/// are drawn, in slot order, the item held in the primary weapon slot, if any, each
/// worn item whose properties the reader refuses, with the reason, each worn item
/// whose visual the tables cannot give, with the reason, and the equip spells of the worn
/// items (`equip_spell`) in worn order, each with its item, once.
pub type Gear {
  Gear(
    properties: ItemProperties,
    visuals: List(ItemVisual),
    weapon: Option(Item2Id),
    unread: List(#(Item2Id, ItemPropertyError)),
    undrawn: List(#(Item2Id, WornVisualError)),
    equip_spells: List(EquipSpell),
  )
}

/// A worn item's equip spell and the item that gives it, whose level the standing cast of the
/// spell tells (`connection/casting.standing_changed`).
pub type EquipSpell {
  EquipSpell(spell4_id: Int, item2_id: Item2Id)
}

/// The gear of the items held at location 0 among `items`, for a wearer of this level:
/// a level-scaled item reads every curve at it.
pub fn of_items(
  tables tables: table_store.Tables,
  items items: List(HeldItem),
  level level: Int,
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
          random_stats: item.words.random_stats,
          level:,
        ),
      )
    })
  let #(given, unread) = keep_one_shield(read:)
  let assert Ok(properties) = item_property.sum(items: given)
    as "at most one shield is kept, so the items sum"
  let seen =
    worn_visual.of_items(
      tables:,
      item2_ids: list.map(worn, fn(item) { item.item2_id }),
    )
  let visuals =
    list.map(seen.drawn, fn(drawn) { worn_visual.item_visual(drawn.visual) })
  let undrawn = seen.undrawn
  let weapon =
    list.find(worn, fn(item) { item.bag_index == weapon_bag_index })
    |> result.map(fn(item) { item.item2_id })
    |> option.from_result
  let equip_spells =
    list.filter_map(worn, fn(item) {
      equip_spell.of_item(tables:, item2_id: item.item2_id.value)
      |> option.map(fn(spell4_id) {
        EquipSpell(spell4_id:, item2_id: item.item2_id)
      })
      |> option.to_result(Nil)
    })
    |> list.unique
  Gear(properties:, visuals:, weapon:, unread:, undrawn:, equip_spells:)
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
/// id order, at its default plus what the worn items give; BaseFocusPool (5) also holds
/// `focus_pool`, the base pool of the player's class in points (0 for a class that holds
/// no Focus), so taking a worn item off returns it to that base, then the 26 base combat
/// properties (`player_combat_bases`).
/// `NoCreatureLevel` when the table has no Base Health row for the level, or no row 101.
pub fn bases(
  tables tables: table_store.Tables,
  gear gear: Gear,
  level level: Int,
  focus_pool focus_pool: Float,
) -> Result(List(#(UnitProperty2Id, Float)), HealthError) {
  use health <- result.try(max_health(tables:, gear:, level:))
  use combat <- result.map(
    player_combat_bases(tables:)
    |> result.replace_error(NoCreatureLevel(
      level: unit_properties.high_property_creature_level,
    )),
  )
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
          +. result.unwrap(dict.get(properties.budget, property_id), 0.0)
          +. case property_id == unit_properties.focus_pool {
          True -> focus_pool
          False -> 0.0
        },
      )
    })
  list.flatten([fixed, budget, combat])
}

/// The 26 UnitProperty2 ids of a player's base combat properties: BaseAvoidChance,
/// BaseCritChance, the mitigation, strikethrough and critical deflect bases (101 to
/// 105), the mitigation offsets and the other bases of the character sheet's rows and
/// the damage taken offsets (144 to 158), the glance chance, the crowd control duration
/// and the PvP offsets (164 to 167), the glance amount and BaseVigor (195, 196). None is
/// worth anything per point, so none is an item budget property, and the gear sets none
/// of them (`player.base_combat_properties`).
const player_combat_ids = [
  101, 102, 103, 104, 105, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154,
  155, 156, 157, 158, 164, 165, 166, 167, 195, 196,
]

/// The base of each of a player's 26 base combat properties: the value of CreatureLevel row
/// 101 at the column of the id less 100, the row the client reads for properties 100 and above
/// whatever the level (`0x1404585c0`): 0.05 for BaseAvoidChance (101) and BaseCritChance (102),
/// 1.0 for CCDurationModifier (165), 0.0 for the other 23, in id order. The server's guess: the
/// client reads CreatureLevel only for a creature and scales it by the creature's archetype,
/// difficulty and tier, none of which a player has, so a player takes the row's value alone
/// (`player.base_combat_properties`). `Error` when the table has no row 101.
pub fn player_combat_bases(
  tables tables: table_store.Tables,
) -> Result(List(#(UnitProperty2Id, Float)), Nil) {
  use row <- result.try(creature_level.get(
    tables:,
    id: CreatureLevelId(unit_properties.high_property_creature_level),
  ))
  let columns = creature_columns.level_values(row:)
  list.try_map(player_combat_ids, fn(property) {
    list.drop(columns, property - 100)
    |> list.first
    |> result.map(fn(base) { #(UnitProperty2Id(property), base) })
  })
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
/// drawing. `None` at entry, where nothing is known yet.
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
    })
  let undrawn =
    new_items(items: gear.undrawn, known: known_undrawn)
    |> list.map(fn(undrawn) {
      worn_visual.describe_undrawn(item2_id: undrawn.0, error: undrawn.1)
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
/// refuses tables without its row (genesis_prime/shared/unit_properties).
fn default_of(
  defaults defaults: List(#(UnitProperty2Id, Float)),
  id id: UnitProperty2Id,
) -> Float {
  let assert Ok(default) = list.key_find(defaults, id)
    as "the load checks that UnitProperty2 has the shield properties' rows"
  default
}

/// What the gear's properties do not do that the client's rows ask for.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Player base combat properties",
      missing: "a player's 26 base combat properties are CreatureLevel row 101's values with no archetype, difficulty or tier factor, which is the server's guess: the client gives a creature those factors and a player none, and no retail record of a player's base chances was found; ids 100 and above other than the 26 stay at their UnitProperty2 defaults for a player",
    ),
  ]
}
