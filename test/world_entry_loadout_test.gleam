//// What world entry sends a character of each class besides the unit: the
//// weapon, the abilities, their tiers and the action set, and what the unit's
//// 0x262 carries of the gear (`genesis_prime/game/world_entry`). Expected values
//// come from these places.
//// - The messages and their order: 0x111 with location 0 for each armor piece
////   and the shield at the bag index of its slot (`ItemSlot.equippedSlotFlags`:
////   chest 0, legs 1, shoulder 3, feet 4, hands 5, shield 15), then 0x111 with
////   location 0 and index 16 for the weapon (`0x1403afb10`: the cast check
////   looks up key location 0, index 16; `lua.ActionBarFrame.InitializeBars`:
////   the bar shows once an item is equipped in slot 16), then 0x111 with
////   location 4 for each ability, the
////   item id the ability's Spell4Base id and the bag index the ability's place
////   in its class's list (`opcode.0x111.ability_bag`); 0x1a0 with tier 1 in
////   action sets 0 to 3 (`opcode.0x1a0`: an entry has four sets); 0x19d for set
////   0 with a type 4 shortcut for bar slot 0, 1 and 2 (`opcode.0x19d`); all
////   after 0x19b, which sets the player, and before 0x61, which ends the entry
////   (`opcode.0x19b`, `opcode.0x61`).
//// - The unit's gear: properties 7 (Base Health), 35 and 36 (Assault Rating and
////   Support Rating), 41 (ShieldCapacityMax), 42 (Armor), 175, 176 and 178
////   (ShieldMitigationMax, ShieldRegenPct and ShieldRebootTime), each with its
////   base and its value, and stats 0 (health) and 20 (shield), which the
////   0x262 sets at create (`0x1404584b0`, `0x140458140`). The values are the
////   Novice set's (`Item2.novice_set`, `player.level1_gear_properties`):
////   Base Health 736, Assault Rating 203.0625, Support Rating 55.6875, Armor
////   250, 200 or 150 by class, shield 450, mitigation 0.625, regeneration 0.15
////   and reboot 5125.
//// - A property's float is compared exactly: the 32-bit float nearest the
////   source's decimal (`float32.rounded`), which is what the client holds
////   (the sums of 7.2 and 5.4 in 64 bits round to the same 32 bits).
//// - The shield on entry is full (stat 20 equal to property 41): a server
////   choice, the client holding no shield rule (`regen.client`).

import cast_support
import character_tables
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/world_entry
import genesis_prime/message/ability_tier.{AbilityTier}
import genesis_prime/message/ability_tiers
import genesis_prime/message/action_set
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/float32
import genesis_prime/message/item_added
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/store.{type Character, HeldItem}
import genesis_prime/table/id.{Item2Id, Spell4BaseId}
import genesis_prime/world_map/unit_fields
import gleam/float
import gleam/int
import gleam/list
import owned_test
import world_entry_support

/// A class's id, its armor, its three Spell4Base ids (the SpellLevel rows of
/// level 1, in id order), its innate's Spell4Base id (Class
/// `spell4IdInnateAbilityActive00`) and the weapon of each faction.
type Class {
  Class(
    id: Int,
    armor: Float,
    abilities: List(Int),
    innate: Int,
    weapon_167: Int,
    weapon_166: Int,
  )
}

fn classes() -> List(Class) {
  [
    Class(1, 250.0, [18_309, 37_968, 38_017], 30_828, 81_346, 81_352),
    Class(2, 250.0, [26_468, 25_473, 25_635], 31_779, 81_347, 81_353),
    Class(3, 150.0, [19_102, 19_019, 19_022], 38_012, 81_351, 81_357),
    Class(4, 200.0, [38_201, 16_322, 26_543], 46_615, 81_348, 81_354),
    Class(5, 200.0, [23_148, 23_161, 23_173], 30_075, 81_349, 81_355),
    Class(7, 150.0, [27_638, 20_684, 20_325], 31_213, 81_350, 81_356),
  ]
}

/// What a character's entry sends and keeps: the entry's frames, in order, and
/// the player the connection keeps.
fn entering(
  character character: Character,
) -> #(List(Frame), world_entry.Entered) {
  let #(effects, entered) =
    world_entry_support.entry(tables: character_tables.shared(), character:)
  #(world_entry_support.frames_of(effects:), entered)
}

fn player_of(frames frames: List(Frame)) -> UnitCreatePlayer {
  let assert Ok(player) =
    unit_create_player.decode(
      { world_entry_support.only_frame(frames:, message_id: 0x0262) }.body,
    )
    as "0x262 decodes"
  player
}

pub fn the_novice_weapon_is_sent_as_an_item_at_location_0_index_16_before_the_abilities_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(frames, _) =
    entering(character: world_entry_support.character(
      class: 2,
      faction: 166,
      level: 1,
    ))
  let items = world_entry_support.items_added(frames:)
  assert list.map(items, fn(added) { added.held_item.item.location })
    == [0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4]
    as "the equipped items come before the abilities: seven at location 0, then the three abilities and the innate at location 4"
  let assert [weapon] =
    list.filter(items, fn(added) {
      added.held_item.item.location == 0 && added.held_item.item.bag_index == 16
    })
    as "one item is equipped in slot 16"
  let abilities =
    list.filter(items, fn(added) {
      added.held_item.item.location == 4 && added.held_item.item.bag_index < 3
    })
  assert weapon.held_item.item.location == 0
    && weapon.held_item.item.bag_index == 16
    as "0x1403afb10: the cast check looks up location 0, index 16; lua.ActionBarFrame.InitializeBars: slot 16 holds the weapon"
  assert weapon.held_item.item.item_id == 81_353
    as "CharacterCreation row 479, the Engineer of faction 166: itemId04 is the weapon 81353"
  assert list.all(abilities, fn(added) { added.held_item.item.location == 4 })
    as "opcode.0x111.ability_bag: an ability's item is at location 4"
  assert list.length(abilities) == 3 as "SpellLevel: three abilities at level 1"
}

pub fn an_item_for_each_ability_at_location_4_holds_the_spell4_base_id_of_each_level_1_spell_of_the_class_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 166,
        level: 1,
      ))
    let abilities =
      world_entry_support.items_added(frames:)
      |> list.filter(fn(added) {
        added.held_item.item.location == 4 && added.held_item.item.bag_index < 3
      })
    assert list.map(abilities, fn(added) { added.held_item.item.item_id })
      == class.abilities
      as {
        "SpellLevel.spell4Id: class "
        <> int.to_string(class.id)
        <> " has three level-1 spells, whose Spell4Base ids are these"
      }
    assert list.map(abilities, fn(added) { added.held_item.item.bag_index })
      == [0, 1, 2]
      as "opcode.0x111.ability_bag: the bag index is the slot a press names, from 0"
    assert list.all(abilities, fn(added) { added.held_item.reason == 49 })
      as "opcode.0x111.ability_bag: reason 49 adds the item without raising the ability book's change"
  })
}

pub fn the_weapon_is_the_classes_and_factions_item_04_for_every_class_and_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    list.each([167, 166], fn(faction) {
      let #(frames, _) =
        entering(character: world_entry_support.character(
          class: class.id,
          faction:,
          level: 1,
        ))
      let assert [weapon] =
        world_entry_support.items_added(frames:)
        |> list.filter(fn(added) {
          added.held_item.item.location == 0
          && added.held_item.item.bag_index == 16
        })
        as "the entry sends the weapon in slot 16"
      assert weapon.held_item.item.item_id
        == case faction {
          167 -> class.weapon_167
          _ -> class.weapon_166
        }
        as "Item2.novice_set: the weapon of the class's PreTutorial row of that faction"
    })
  })
}

pub fn one_0x1a0_sets_tier_1_of_each_ability_in_action_sets_0_to_3_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 166,
        level: 1,
      ))
    let assert Ok(tiers) =
      ability_tiers.decode(
        { world_entry_support.only_frame(frames:, message_id: 0x01A0) }.body,
      )
      as "0x1a0 decodes"
    let expected =
      list.flat_map(list.append(class.abilities, [class.innate]), fn(base) {
        list.map([0, 1, 2, 3], fn(action_set_index) {
          AbilityTier(spell4_base_id: base, tier: 1, action_set_index:)
        })
      })
    assert tiers.tiers == expected
      as "opcode.0x1a0: an entry holds four action sets, and tier 1 is each ability's and the innate's first"
  })
}

pub fn one_0x19d_sets_action_set_0_with_the_three_abilities_in_bar_slots_0_to_2_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 166,
        level: 1,
      ))
    let assert Ok(set) =
      action_set.decode(
        { world_entry_support.only_frame(frames:, message_id: 0x019D) }.body,
      )
      as "0x19d decodes"
    assert set.action_set_index == 0 && set.result == 1
      as "opcode.0x19d: set 0, which is active until a message changes it, and result 1, ok"
    assert set.field_2 == 1
      as "opcode.0x19d.set_value: bit 0 marks the set unlocked, and the active set is unlocked"
    assert set.shortcuts
      == list.index_map(class.abilities, fn(base, slot) {
        ActionShortcut(
          shortcut_type: 4,
          location: 4,
          bag_index: slot,
          object_id: base,
        )
      })
      as "opcode.0x19d: type 4 is an ability by its Spell4Base id, the bag index is the bar slot, 0 to 2 for the large buttons"
  })
}

pub fn the_loadout_comes_after_0x19b_and_before_0x61_with_the_equipped_items_first_and_the_set_last_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(frames, _) =
    entering(character: world_entry_support.character(
      class: 4,
      faction: 166,
      level: 1,
    ))
  assert cast_support.ids(frames:)
    == [
      0x00AD,
      0x0262,
      0x019B,
      0x092C,
      0x025E,
      0x035F,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x0111,
      0x01A0,
      0x019D,
      0x019F,
      0x06BC,
      0x0636,
      0x00F1,
      0x0061,
    ]
    as "opcode.0xad, opcode.0x262, opcode.0x19b first as before; then the five armor pieces, the shield and the weapon, the three abilities and the innate, their tiers, the action set and the innate button (0x19f), which all follow 0x19b (it sets the player) and come before 0x61 (it ends the entry); the rest as before"
}

/// The value a property holds, as the 32-bit float the client reads.
fn property_value(
  properties properties: List(UnitProperty),
  id id: Int,
) -> Float {
  let assert Ok(property) =
    list.find(properties, fn(property) { property.property_id == id })
    as { "0x262 holds property " <> int.to_string(id) }
  let assert Ok(bits) = float32.bits(property.value)
    as "a property value is 32 bits"
  let assert Ok(value) = float32.value(bits) as "a property value is finite"
  assert property.base == property.value
    as "0x1404584b0: a property sets its base and its value, which a worn item gives alike"
  value
}

fn stat(player player: UnitCreatePlayer, id id: Int) -> Int {
  let assert Ok(value) = unit_fields.stat(tail: player.tail, stat_id: id)
    as { "0x262 holds stat " <> int.to_string(id) <> " as an integer" }
  value
}

pub fn property_7_and_stat_0_are_736_for_every_class_and_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    list.each([167, 166], fn(faction) {
      let #(frames, _) =
        entering(character: world_entry_support.character(
          class: class.id,
          faction:,
          level: 1,
        ))
      let player = player_of(frames:)
      assert property_value(properties: player.tail.properties, id: 7) == 736.0
        as "player.level1_base_health: 135.97 (CreatureLevel row 1) and 600 (the Novice armor), 736; Unit:GetMaxHealth reads property 7 (0x14064a6d0)"
      assert stat(player:, id: 0) == 736
        as "0x140458140: stat 0 is health, 736 at full"
    })
  })
}

pub fn properties_35_and_36_are_203_0625_and_55_6875_for_every_class_and_faction_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    list.each([167, 166], fn(faction) {
      let #(frames, _) =
        entering(character: world_entry_support.character(
          class: class.id,
          faction:,
          level: 1,
        ))
      let properties = player_of(frames:).tail.properties
      assert property_value(properties: properties, id: 35)
        == float32.rounded(203.0625)
        as "0x14040df10: the weapon's Assault Rating 167.0625 and the armor's 36.0"
      assert property_value(properties: properties, id: 36)
        == float32.rounded(55.6875)
        as "0x14040df10: the weapon's Support Rating 55.6875"
    })
  })
}

pub fn property_42_is_250_for_heavy_200_for_medium_and_150_for_light_armor_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 166,
        level: 1,
      ))
    assert property_value(
        properties: player_of(frames:).tail.properties,
        id: 42,
      )
      == float32.rounded(class.armor)
      as "0x14040e340: armor 40 x the category's and each slot's modifier, summed over the set"
  })
}

pub fn property_41_is_450_and_properties_175_176_and_178_are_the_shield_items_values_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 166,
        level: 1,
      ))
    let properties = player_of(frames:).tail.properties
    assert property_value(properties: properties, id: 41)
      == float32.rounded(450.0)
      as "0x14040dbf0: ShieldCapacityMax 450"
    assert property_value(properties: properties, id: 175)
      == float32.rounded(0.625)
      as "0x14040dbf0: ShieldMitigationMax 0.625"
    assert property_value(properties: properties, id: 176)
      == float32.rounded(0.15)
      as "0x14040dbf0: ShieldRegenPct 0.15, in place of the unit property default 0.25 (a server choice: the item's value replaces the default, the client summing nothing)"
    assert property_value(properties: properties, id: 178) == 5125.0
      as "0x14040dbf0: ShieldRebootTime 5125, in place of the default 2500 (the same server choice)"
  })
}

pub fn stat_20_the_current_shield_equals_property_41_at_entry_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 166,
        level: 1,
      ))
    let player = player_of(frames:)
    assert stat(player:, id: 20) == 450
      && float.round(property_value(properties: player.tail.properties, id: 41))
      == 450
      as "a full shield on entry: stat 20, the current shield, equals property 41, the maximum (a server choice: the client holds no shield rule)"
  })
}

pub fn the_unit_the_player_keeps_for_those_who_see_it_is_the_unit_it_was_sent_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(frames, entered) =
    entering(character: world_entry_support.character(
      class: 1,
      faction: 167,
      level: 1,
    ))
  assert entered.unit == player_of(frames:)
    as "a player that sees another is sent the same 0x262, gear included"
}

pub fn a_level_9_players_health_adds_the_armors_600_to_the_creature_level_rows_base_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(frames, _) =
    entering(character: world_entry_support.character(
      class: 4,
      faction: 166,
      level: 9,
    ))
  let player = player_of(frames:)
  assert stat(player:, id: 0) == 2895
    && property_value(properties: player.tail.properties, id: 7) == 2895.0
    as "player.level1_base_health: the CreatureLevel row of the level, here the planted row 9's 2295.49, and the armor's 600"
}

pub fn the_player_the_connection_keeps_holds_its_loadout_and_its_max_health_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, entered) =
    entering(character: world_entry_support.character(
      class: 2,
      faction: 166,
      level: 1,
    ))
  assert entered.loadout.weapon == Item2Id(81_353)
    && entered.loadout.weapon_slot == 16
    && entered.loadout.abilities
    == [Spell4BaseId(26_468), Spell4BaseId(25_473), Spell4BaseId(25_635)]
    as "the typed loadout: CharacterCreation row 479's weapon in slot 16 and the Engineer's three Spell4Base ids"
  assert entered.max_health == 736
    as "player.level1_base_health: the typed maximum health the 0x262 carries"
  assert entered.loadout.properties.armor == 250.0
    as "the typed gear: the Engineer's heavy armor, 250"
}

pub fn the_abilities_items_have_guids_of_their_own_that_are_not_0_and_not_a_held_items_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(classes(), fn(class) {
    let #(frames, _) =
      entering(character: world_entry_support.character(
        class: class.id,
        faction: 167,
        level: 1,
      ))
    let added = world_entry_support.items_added(frames:)
    let #(abilities, held) =
      list.partition(added, fn(added) { added.held_item.item.location == 4 })
    let ability_guids =
      list.map(abilities, fn(added) { added.held_item.item.item_guid })
    let held_guids =
      list.map(held, fn(added) { added.held_item.item.item_guid })
    assert list.length(ability_guids) == 4
      as "opcode.0x111.ability_bag: the three abilities and the innate"
    assert list.length(list.unique(ability_guids)) == 4
      as "opcode.0x111.guid: each ability item has a guid of its own"
    assert !list.contains(ability_guids, 0)
      as "opcode.0x111.guid: a guid is never 0"
    assert !list.any(ability_guids, fn(guid) { list.contains(held_guids, guid) })
      as "opcode.0x111.guid: the client finds an item by its guid, so an ability item never takes the guid of a held item"
  })
}

pub fn the_entry_sends_an_item_added_for_each_saved_item_with_its_saved_guid_and_place_test() -> Nil {
  use <- owned_test.run(10_000)
  let character =
    world_entry_support.character(class: 2, faction: 166, level: 1)
  let saved = [
    HeldItem(
      item_guid: 12,
      item2_id: Item2Id(81_366),
      location: 1,
      bag_index: 3,
      stack_count: 5,
    ),
    HeldItem(
      item_guid: 5_000_000_001,
      item2_id: Item2Id(81_353),
      location: 0,
      bag_index: 16,
      stack_count: 1,
    ),
    HeldItem(
      item_guid: 7,
      item2_id: Item2Id(8535),
      location: 0,
      bag_index: 15,
      stack_count: 1,
    ),
  ]
  let #(effects, entered) =
    world_entry_support.entry_holding(
      tables: character_tables.shared(),
      character:,
      items: saved,
    )
  let frames = world_entry_support.frames_of(effects:)
  let added = world_entry_support.items_added(frames:)
  let held = fn(added: item_added.ItemAdded) {
    let item = added.held_item.item
    #(
      item.location,
      item.bag_index,
      item.item_guid,
      item.item_id,
      item.stack_count,
    )
  }
  assert list.take(list.map(added, held), 3)
    == [
      #(0, 15, 7, 8535, 1),
      #(0, 16, 5_000_000_001, 81_353, 1),
      #(1, 3, 12, 81_366, 5),
    ]
    as "opcode.0x111.guid: the message carries the item's whole 64-bit guid, so a guid above 2^32 and one at inventory 1/3 go out as saved; the items go in the order of their places, by location then bag index (the order the store reads them in, whatever the order of the list)"
  assert list.map(added, fn(added) { added.held_item.item.location })
    == [0, 0, 1, 4, 4, 4, 4]
    as "one item added for each saved item and none more for the loadout's gear; the three abilities and the innate (location 4, opcode.0x111.ability_bag) follow as before"
  assert list.all(added, fn(added) { added.held_item.item.item_guid != 0 })
    as "opcode.0x111.equipped_set: a guid is never 0"
  assert entered.items == saved
    as "the player the connection keeps holds the items as they were saved"
  let ids = cast_support.ids(frames:)
  let #(before_tiers, from_tiers) =
    list.split_while(ids, fn(id) { id != 0x01A0 })
  assert list.count(before_tiers, fn(id) { id == 0x0111 }) == 7
    && !list.contains(from_tiers, 0x0111)
    as "every item added, the three saved and the four abilities, comes before the tiers (0x1a0) and the action set"
  assert entered.loadout.weapon == Item2Id(81_353)
    && entered.loadout.weapon_slot == 16
    as "casting still reads the weapon from the loadout (0x1403afb10: location 0, index 16)"

  let #(effects, entered) =
    world_entry_support.entry_holding(
      tables: character_tables.shared(),
      character: world_entry_support.character(class: 2, faction: 166, level: 1),
      items: [],
    )
  let frames = world_entry_support.frames_of(effects:)
  let added = world_entry_support.items_added(frames:)
  assert list.map(added, fn(added) { added.held_item.item.location })
    == [4, 4, 4, 4]
    as "a character saved before items were stored holds no gear; its three abilities and the innate go out at location 4 (opcode.0x111.ability_bag)"
  assert list.map(added, fn(added) { added.held_item.item.item_id })
    == [26_468, 25_473, 25_635, 31_779]
    as "SpellLevel level 1 of the Engineer and its innate's Spell4Base id, as with gear"
  assert list.length(
      list.filter(cast_support.ids(frames:), fn(id) {
        id == 0x01A0 || id == 0x019D
      }),
    )
    == 2
    as "the tiers (0x1a0) and the action set (0x19d) go out as before"
  assert entered.loadout.weapon == Item2Id(81_353)
    as "casting reads the weapon from the loadout"
}
