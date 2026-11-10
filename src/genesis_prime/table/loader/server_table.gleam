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
import genesis_prime/table/currency_type
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/episode
import genesis_prime/table/episode_quest
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
import genesis_prime/table/item_proficiency
import genesis_prime/table/item_slot
import genesis_prime/table/item_special
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/requirement
import genesis_prime/table/loader/store
import genesis_prime/table/path_mission
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/periodic_quest_group
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/race
import genesis_prime/table/reward_property_premium_modifier
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
import genesis_prime/table/target_group
import genesis_prime/table/telegraph_damage
import genesis_prime/table/tradeskill_schematic2
import genesis_prime/table/tutorial
import genesis_prime/table/unit_property2
import genesis_prime/table/world
import genesis_prime/table/world_location2
import genesis_prime/table/world_zone
import genesis_prime/table/xp_per_level

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
/// - CurrencyType: the cap of a currency other than credits and Renown
///   (genesis_prime/game/currency).
/// - CustomizationParameter and CustomizationParameterMap: the bone values a
///   create request carries (genesis_prime/game/appearance).
/// - GameFormula and XpPerLevel: the starting level (genesis_prime/game/level).
/// - CreatureLevel: a player's Base Health by level (genesis_prime/game/loadout).
/// - Item2, Item2Category, Item2Family, Item2Type and ItemSlot, with GameFormula:
///   the Novice gear's properties (genesis_prime/game/item_property).
/// - ItemProficiency and ItemSpecial, with Item2 and Item2Category: whether a
///   character may wear an item (genesis_prime/game/item_property and
///   genesis_prime/game/equip_requirement).
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
/// - Prerequisite: the gate of a spell's resource gains and Proxies
///   (genesis_prime/game/spell_plan) and the caster prerequisite of a creature attack's
///   damage effects, which the content load reads (genesis_prime/world_map/creature_attack).
/// - PositionalRequirement: the arc a type 108 prerequisite condition names
///   (genesis_prime/game/prerequisite).
/// - Quest2 and QuestObjective: the quests a saved quest log may name, each with its
///   objectives and period (genesis_prime/game/quest_log), and the quests a
///   prerequisite's quest conditions name (genesis_prime/game/prerequisite).
/// - TargetGroup: the units a kill objective counts (genesis_prime/game/target_group).
/// - TradeskillSchematic2: the item a type 33 objective counts (genesis_prime/game/objective).
/// - Episode, EpisodeQuest and PeriodicQuestGroup, with Quest2 and GameFormula: whether
///   a player may accept a quest (genesis_prime/game/quest).
/// - PathSoldierActivate: whether a type 28 objective is a checklist, which a
///   prerequisite's progress condition reads (genesis_prime/game/prerequisite).
/// - Race: a player's hit radius (genesis_prime/game/hit_radius).
/// - RewardPropertyPremiumModifier: the bag and bank slots a premium tier gives
///   (genesis_prime/game/reward_property).
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
    currency_type.entry(),
    customization_parameter.entry(),
    customization_parameter_map.entry(),
    episode.entry(),
    episode_quest.entry(),
    game_formula.entry(),
    instance_portal.entry(),
    item2.entry(),
    item2_category.entry(),
    item2_family.entry(),
    item2_type.entry(),
    item_display.entry(),
    item_display_source_entry.entry(),
    item_proficiency.entry(),
    item_slot.entry(),
    item_special.entry(),
    path_mission.entry(),
    path_soldier_activate.entry(),
    periodic_quest_group.entry(),
    positional_requirement.entry(),
    prerequisite.entry(),
    quest2.entry(),
    quest_objective.entry(),
    race.entry(),
    reward_property_premium_modifier.entry(),
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
    target_group.entry(),
    telegraph_damage.entry(),
    tradeskill_schematic2.entry(),
    unit_property2.entry(),
    world_location2.entry(),
    world_zone.entry(),
    xp_per_level.entry(),
  ]
}

/// The entries only the content load reads (genesis_prime/content), listed apart
/// from `entries` so that they are read beside the server's tables on the caller's
/// heap and the server's tables hold only what its rules read:
/// - Creature2OutfitInfo: the outfit of a spawn (genesis_prime/world_map/spawn).
/// - Faction2 and Faction2Relationship: which creatures a player can attack
///   (genesis_prime/world_map/spawn).
/// - World: the worlds a map can run in, each of which gets a term of its spawns
///   (genesis_prime/world_map/spawn).
/// - Tutorial: the category of each row a zone's welcome names
///   (genesis_prime/game/zone_welcome).
pub fn content_entries() -> List(store.Entry) {
  [
    creature2_outfit_info.entry(),
    faction2.entry(),
    faction2_relationship.entry(),
    tutorial.entry(),
    world.entry(),
  ]
}

/// The content-only tables, read beside the server's own `tables` on the
/// caller's heap, so the content load reads the creature tables already loaded
/// and loads nothing twice. Nothing is stored, so there is nothing to unload.
pub fn load_content_tables(
  over tables: store.Tables,
  from folder: String,
) -> Result(store.Tables, store.LoadError) {
  store.read_more(over: tables, from: folder, entries: content_entries())
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

/// The server's tables read from `folder` on the caller's heap, stored under
/// no key, for a test that reads the server's tables from planted files.
pub fn read(from folder: String) -> Result(store.Tables, store.LoadError) {
  store.read(
    from: folder,
    entries: entries(),
    requirements: requirement.all(),
    derivations: derivation.all(),
  )
}
