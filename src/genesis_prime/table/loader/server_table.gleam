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
import genesis_prime/table/class
import genesis_prime/table/creature2
import genesis_prime/table/creature2_arche_type
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/creature2_display_group_entry
import genesis_prime/table/creature2_display_info
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/creature2_resist
import genesis_prime/table/creature2_tier
import genesis_prime/table/creature_level
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/faction2
import genesis_prime/table/faction2_relationship
import genesis_prime/table/game_formula
import genesis_prime/table/instance_portal
import genesis_prime/table/item2
import genesis_prime/table/item2_category
import genesis_prime/table/item2_family
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_display_source_entry
import genesis_prime/table/item_slot
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/requirement
import genesis_prime/table/loader/store
import genesis_prime/table/path_mission
import genesis_prime/table/prerequisite
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/spell4_stack_group
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import genesis_prime/table/telegraph_damage
import genesis_prime/table/unit_property2
import genesis_prime/table/world
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
/// - ItemDisplay and ItemDisplaySourceEntry: what a worn item is drawn with
///   (genesis_prime/game/worn_visual).
/// - Spell4 and SpellLevel: a class's level-1 abilities (genesis_prime/game/loadout).
/// - Spell4, Spell4Base, Spell4Conditions, Spell4Effects, Spell4Thresholds,
///   SpellPhase, SpellCoolDown and Class: the tree of casts each of those abilities
///   starts, the stages of a RapidTap or ChargeRelease one, and whether its caster
///   may be dead (genesis_prime/game/spell_plan).
/// - Spell4GroupList and Spell4StackGroup: the spell groups a Spell4Effects type 80 row
///   removes by and the stack group and cap of a spell that lasts on a unit
///   (genesis_prime/game/spell_plan).
/// - Spell4, Spell4AoeTargetConstraints, Spell4Telegraph, TelegraphDamage,
///   Spell4ValidTargets and Spell4Effects: what each spell strikes, its area, hit
///   shapes and damage effects (genesis_prime/game/spell_area).
/// - GameFormula and UnitProperty2: the hit rule's rating formulas and a player's
///   bases (genesis_prime/game/rating); with CreatureLevel and the creature tables, a
///   creature's defence (genesis_prime/world_map/spawn).
/// - Prerequisite: the gate of a spell's resource gains (genesis_prime/game/spell_plan)
///   and the caster prerequisite of a creature attack's damage effects, which the
///   content load reads (genesis_prime/world_map/creature_attack).
/// - WorldLocation2: the start places (genesis_prime/game/start_place).
/// - WorldZone: the top zone of each zone (genesis_prime/game/top_zone).
pub fn entries() -> List(store.Entry) {
  [
    character_creation.entry(),
    chat_channel.entry(),
    class.entry(),
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
    item_display.entry(),
    item_display_source_entry.entry(),
    item_slot.entry(),
    path_mission.entry(),
    prerequisite.entry(),
    spell4.entry(),
    spell4_aoe_target_constraints.entry(),
    spell4_base.entry(),
    spell4_conditions.entry(),
    spell4_effects.entry(),
    spell4_group_list.entry(),
    spell4_stack_group.entry(),
    spell4_telegraph.entry(),
    spell4_thresholds.entry(),
    spell4_valid_targets.entry(),
    spell_cool_down.entry(),
    spell_level.entry(),
    spell_phase.entry(),
    telegraph_damage.entry(),
    unit_property2.entry(),
    world_location2.entry(),
    world_zone.entry(),
    xp_per_level.entry(),
  ]
}

/// The entries only the content load reads (genesis_prime/content), listed apart
/// from `entries` so the tables digest of a recording does not change with them:
/// - Creature2OutfitInfo: the outfit of a spawn (genesis_prime/world_map/spawn).
/// - Faction2 and Faction2Relationship: which creatures a player can attack
///   (genesis_prime/world_map/spawn).
/// - World: the worlds a map can run in, each of which gets a term of its spawns
///   (genesis_prime/world_map/spawn).
fn content_entries() -> List(store.Entry) {
  [
    creature2_outfit_info.entry(),
    faction2.entry(),
    faction2_relationship.entry(),
    world.entry(),
  ]
}

/// The content-only tables, loaded beside the server's own `tables` under the
/// key they were loaded under, so the content load reads the creature tables
/// already loaded and loads nothing twice. Gives only the content-only ones: the
/// caller unloads them once the content is loaded, and the server's own stay.
pub fn load_content_tables(
  over tables: store.Tables,
  from folder: String,
) -> Result(store.Tables, store.LoadError) {
  store.load_more(over: tables, from: folder, entries: content_entries())
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
