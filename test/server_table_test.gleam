//// The tables the server loads at its start (`genesis_prime/table/loader/
//// server_table`). Expected values are these.
//// - The list: the tables the server's rules read. Of the client's 384,
////   the Creature2 table with its ArcheType, Difficulty, DisplayGroupEntry,
////   DisplayInfo, OutfitGroupEntry, OverrideProperties, Resist and Tier, with
////   InstancePortal and PathMission
////   (`genesis_prime/world_map/spawn`),
////   CharacterCreation (the create request's row, the Novice set), CharacterCustomization,
////   CharacterCustomizationLabel (the look's rows and labels),
////   CustomizationParameter and CustomizationParameterMap (the bone counts),
////   WorldLocation2 (the start places), GameFormula and XpPerLevel (the
////   starting level and the item formulas), ChatChannel and WorldZone (chat),
////   and Item2, Item2Category, Item2Family, Item2Type, ItemSlot, Spell4,
////   SpellLevel and CreatureLevel (the Novice loadout,
////   `genesis_prime/game/loadout`), with ItemDisplay and ItemDisplaySourceEntry
////   (what a worn item is drawn with, `genesis_prime/game/worn_visual`), and
////   Quest2 and QuestObjective (the quests a saved log names and their
////   objective slots, `genesis_prime/game/quest_log`), and
////   RewardPropertyPremiumModifier (the bag and bank slots of a signature
////   tier, `genesis_prime/game/reward_property`), CurrencyType (the cap of a
////   currency, `genesis_prime/game/currency`), and TargetGroup (the groups of
////   units a kill objective counts, `genesis_prime/game/target_group`), and
////   Quest2Reward (the rewards of a quest a turn-in gives,
////   `genesis_prime/game/quest_turn_in`), and Quest2Difficulty and
////   LevelDifferentialAttribute (the multipliers of a quest's experience and credits,
////   `genesis_prime/game/quest_turn_in`), and CommunicatorMessages (the rows that deliver a
////   quest over the communicator), Faction2 and Faction2Relationship (the levels of one faction
////   toward another, `genesis_prime/game/faction_level`) are the ones a rule reads today.
//// - The load: one file for each table of the list and no other is read, the
////   rows the rules follow are required, and a missing row fails the load. The
////   load runs in a fresh node, since it is under the server's own key, which
////   a load in the test node would take from the tests that hold it.

import fixture_tables
import fresh_node
import genesis_prime/game/appearance
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/store.{LookEntry}
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/id.{CharacterCustomizationLabelId, RaceId}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/string
import owned_test
import planted_table
import simplifile

pub fn the_servers_tables_are_the_seventy_one_its_rules_read_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.map(server_table.entries(), fn(entry) {
      table_store.schema(entry).table
    })
    |> list.sort(string.compare)
    == [
      "CharacterCreation",
      "CharacterCustomization",
      "CharacterCustomizationLabel",
      "ChatChannel",
      "Class",
      "CommunicatorMessages",
      "Creature2",
      "Creature2ArcheType",
      "Creature2Difficulty",
      "Creature2DisplayGroupEntry",
      "Creature2DisplayInfo",
      "Creature2OutfitGroupEntry",
      "Creature2OverrideProperties",
      "Creature2Resist",
      "Creature2Tier",
      "CreatureLevel",
      "CurrencyType",
      "CustomizationParameter",
      "CustomizationParameterMap",
      "Episode",
      "EpisodeQuest",
      "Faction2",
      "Faction2Relationship",
      "GameFormula",
      "InstancePortal",
      "Item2",
      "Item2Category",
      "Item2Family",
      "Item2Type",
      "ItemBudget",
      "ItemDisplay",
      "ItemDisplaySourceEntry",
      "ItemProficiency",
      "ItemRandomStat",
      "ItemSlot",
      "ItemSpecial",
      "ItemStat",
      "LevelDifferentialAttribute",
      "PathMission",
      "PathSoldierActivate",
      "PeriodicQuestGroup",
      "PositionalRequirement",
      "Prerequisite",
      "Quest2",
      "Quest2Difficulty",
      "Quest2Reward",
      "QuestDirection",
      "QuestDirectionEntry",
      "QuestObjective",
      "Race",
      "RewardPropertyPremiumModifier",
      "Spell4",
      "Spell4AoeTargetConstraints",
      "Spell4Base",
      "Spell4Conditions",
      "Spell4Effects",
      "Spell4GroupList",
      "Spell4StackGroup",
      "Spell4Telegraph",
      "Spell4Thresholds",
      "Spell4ValidTargets",
      "SpellCoolDown",
      "SpellLevel",
      "SpellPhase",
      "TargetGroup",
      "TelegraphDamage",
      "TradeskillSchematic2",
      "UnitProperty2",
      "WorldLocation2",
      "WorldZone",
      "XpPerLevel",
    ]
    as "the tables the server's rules read: the create request's row, the look, the bone counts, the start places, the zones' top zones, the starting level, the Novice loadout's gear, what it is drawn with, abilities and health, the stages of an ability's taps and charge levels, the spell groups and stack groups of the spells that last on a unit, whether an ability's caster may be dead (Spell4.spell4ConditionsIdCaster), the training creatures' rows, what each spell strikes, the hit rule's formulas and bases, the prerequisites that gate a spell's resource gains, a Proxy's child and a creature attack's effects, the arcs a position condition names, the episodes, the quests of each and the periodic groups whose rules the accept check reads (Episode, EpisodeQuest, PeriodicQuestGroup, read by `quest`), the quests and their objectives a saved quest log is checked against (Quest2 and QuestObjective, read by the quest log at a load and a login, and by a prerequisite's quest conditions at a load), whether a type 28 objective is a checklist (PathSoldierActivate), the hit radius of each playable race (Race.hitRadius), the cap of each currency other than credits and Renown (CurrencyType.capAmount, read by `currency`), and the tables an equip check reads (ItemProficiency for an item category's proficiency mask and ItemSpecial for the prerequisite a special gives), the premium rows that give a signature tier its bag and bank slots (RewardPropertyPremiumModifier, read by `reward_property`), the groups of units a kill objective counts (TargetGroup, read by `target_group`), the rewards of a quest and the multipliers of its experience and credits (Quest2Reward, Quest2Difficulty and LevelDifferentialAttribute, read by `quest_turn_in`), and the budget and stat rows an item's properties come from (ItemBudget and ItemStat, read by `item_property`), the rows a random-stat entry may pick by group (ItemRandomStat, read by `random_stat` and `item_property`), and the schematic whose output item a made-item objective counts (TradeskillSchematic2, read by `objective`), and the places a checklist objective counts the unit under (QuestDirection and QuestDirectionEntry, read by `place_objective`)"
}

/// Runs a function of this module in a fresh node, which must return.
fn in_a_fresh_node(function: String) -> Nil {
  fresh_node.must_return(module: "server_table_test", function:)
}

/// Loads a folder of the committed fixture files of the server's tables, with
/// the server's own load, and reads the appearance index the load built.
pub fn fixture_load() -> Nil {
  use folder <- planted_table.in_folder(fixture_tables.server_files())
  let assert Ok(tables) = server_table.load(from: folder)
    as "a folder with a file for each of the server's tables and no other loads"
  let visuals =
    appearance.body_visuals(
      index: appearance.index(tables:),
      race_id: RaceId(1),
      sex: 0,
      faction_id: 167,
      look: [
        LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
        LookEntry(label: CharacterCustomizationLabelId(22), value: 1),
      ],
    )
  assert visuals
    == [ItemVisual(slot: 25, display_id: 135, item_color_set_id: 0, dye: 0)]
    as "CharacterCustomization row 2 (race 1, gender 0, slot 25, display 135, labels 22 = 1 and 2 = 1; label 22 is faction 167's): an Exile human male shows display 135 in slot 25, from the index the load built"
}

pub fn the_server_load_reads_the_committed_fixture_files_test() -> Nil {
  use <- owned_test.run(60_000)
  in_a_fresh_node("fixture_load")
}

/// Loads the committed fixture files of the server's tables but for
/// CustomizationParameter's.
pub fn load_without_the_parameter_file() -> Nil {
  let files =
    list.filter(fixture_tables.server_files(), fn(file) {
      file.0 != customization_parameter.schema.file
    })
  use folder <- planted_table.in_folder(files)
  assert server_table.load(from: folder)
    == Error(table_store.TableFileUnreadable(
      file: "CustomizationParameter",
      reason: simplifile.Enoent,
    ))
    as "the server's load fails on a folder without a file of its list, naming the file"
}

pub fn a_folder_without_the_customization_parameter_file_is_refused_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  in_a_fresh_node("load_without_the_parameter_file")
}

pub fn the_servers_load_refuses_a_map_naming_a_missing_parameter_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok([_, _, _, _, planted_table.Integer(parameter_id), ..]) =
    list.first(fixture_tables.committed_rows(customization_parameter_map.schema))
    as "a committed CustomizationParameterMap row holds customizationParameterId fifth"
  let files =
    list.key_set(
      fixture_tables.server_files(),
      customization_parameter.schema.file,
      planted_table.file(
        customization_parameter.schema,
        planted_table.without(
          rows: fixture_tables.committed_rows(customization_parameter.schema),
          ids: [parameter_id],
        ),
      ).1,
    )
  use folder <- planted_table.in_folder(files)
  assert server_table.read(from: folder)
    == Error(table_store.RowMissing(
      from_table: "CustomizationParameterMap",
      column: "customizationParameterId",
      to_table: "CustomizationParameter",
      id: parameter_id,
    ))
    as "the server's load fails on a CustomizationParameterMap row that names a CustomizationParameter row the table lacks, naming it"
}
