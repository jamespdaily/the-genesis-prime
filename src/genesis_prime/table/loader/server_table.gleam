//// The tables the server loads at its start: the ones its rules read, not all
//// the client's. Each entry is a table that a module outside
//// `genesis_prime/table/` reads, and a test fails when a module reads a table
//// that is missing here (a new engine that reads a table adds it) or when an
//// entry is read by none. The coverage tool and the tests of the client's
//// tables load every table (`genesis_prime/table.load`).

import genesis_prime/table/character_creation
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/chat_channel
import genesis_prime/table/creature2
import genesis_prime/table/creature2_arche_type
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/creature2_display_group_entry
import genesis_prime/table/creature2_display_info
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/creature2_resist
import genesis_prime/table/creature2_tier
import genesis_prime/table/creature_level
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/game_formula
import genesis_prime/table/instance_portal
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_slot
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/requirement
import genesis_prime/table/loader/store
import genesis_prime/table/path_mission
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import genesis_prime/table/world_location2
import genesis_prime/table/world_zone
import genesis_prime/table/xp_per_level
import gleam/erlang/reference.{type Reference}

/// The entry of each table the server loads, in file-name order.
/// - CharacterCreation: the row a create request names
///   (genesis_prime/game/character_creation).
/// - ChatChannel: the flags of each chat channel (genesis_prime/game/chat).
/// - CharacterCustomization and CharacterCustomizationLabel: the rows and
///   labels of a character's look (genesis_prime/game/appearance).
/// - Creature2 with its ArcheType, Difficulty, DisplayGroupEntry, DisplayInfo,
///   OutfitGroupEntry, OverrideProperties, Resist and Tier, InstancePortal and
///   PathMission, and CreatureLevel: the creatures that stand and their values
///   (genesis_prime/world_map/spawn).
/// - CustomizationParameter and CustomizationParameterMap: the bone values a
///   create request carries (genesis_prime/game/appearance).
/// - GameFormula and XpPerLevel: the starting level (genesis_prime/game/level).
/// - CreatureLevel: a player's Base Health by level (genesis_prime/game/loadout).
/// - Item2, Item2Category, Item2Family, Item2Type and ItemSlot, with GameFormula:
///   the Novice gear's properties (genesis_prime/game/item_property).
/// - Spell4 and SpellLevel: a class's level-1 abilities (genesis_prime/game/loadout).
/// - WorldLocation2: the start places (genesis_prime/game/start_place).
/// - WorldZone: the top zone of each zone (genesis_prime/game/top_zone).
pub fn entries() -> List(store.Entry) {
  [
    character_creation.entry(),
    chat_channel.entry(),
    character_customization.entry(),
    character_customization_label.entry(),
    creature2.entry(),
    creature2_arche_type.entry(),
    creature2_difficulty.entry(),
    creature2_display_group_entry.entry(),
    creature2_display_info.entry(),
    creature2_outfit_group_entry.entry(),
    creature2_override_properties.entry(),
    creature2_resist.entry(),
    creature2_tier.entry(),
    creature_level.entry(),
    customization_parameter.entry(),
    customization_parameter_map.entry(),
    game_formula.entry(),
    instance_portal.entry(),
    item2.entry(),
    item2_category.entry(),
    item2_family.entry(),
    item2_type.entry(),
    item_slot.entry(),
    path_mission.entry(),
    spell4.entry(),
    spell_level.entry(),
    world_location2.entry(),
    world_zone.entry(),
    xp_per_level.entry(),
  ]
}

/// Loads the server's tables under the server's own key, the same in every
/// run, from the folder that holds the client's extracted `.tbl` files: each
/// table of `entries`, the rows the server requires, and the values built once
/// from them. The load of the server's start and of a test that replays a
/// recording.
pub fn load(from folder: String) -> Result(store.Tables, store.LoadError) {
  store.load_for_server(
    from: folder,
    entries: entries(),
    requirements: requirement.all(),
    derivations: derivation.all(),
  )
}

/// `load` under a key made for the load, for a test that loads the server's
/// tables from planted files without taking the server's key from the others
/// that hold it.
pub fn load_under(
  under key: Reference,
  from folder: String,
) -> Result(store.Tables, store.LoadError) {
  store.load(
    under: key,
    from: folder,
    entries: entries(),
    requirements: requirement.all(),
    derivations: derivation.all(),
  )
}
