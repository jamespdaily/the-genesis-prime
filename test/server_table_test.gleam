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
////   (what a worn item is drawn with, `genesis_prime/game/worn_visual`) are the
////   ones a rule reads today.
//// - The load: one file for each table of the list and no other is read, the
////   rows the rules follow are required, and a missing row fails the load. The
////   load runs in a fresh node, since it is under the server's own key, which
////   a load in the test node would take from the tests that hold it.

import character_tables
import fresh_node
import genesis_prime/game/appearance
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/store.{LookEntry}
import genesis_prime/table/id.{CharacterCustomizationLabelId, RaceId}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/string
import owned_test
import planted_table

pub fn the_servers_tables_are_the_forty_six_its_rules_read_test() -> Nil {
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
      "CustomizationParameter",
      "CustomizationParameterMap",
      "GameFormula",
      "InstancePortal",
      "Item2",
      "Item2Category",
      "Item2Family",
      "Item2Type",
      "ItemDisplay",
      "ItemDisplaySourceEntry",
      "ItemSlot",
      "PathMission",
      "Prerequisite",
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
      "TelegraphDamage",
      "UnitProperty2",
      "WorldLocation2",
      "WorldZone",
      "XpPerLevel",
    ]
    as "the tables the server's rules read: the create request's row, the look, the bone counts, the start places, the zones' top zones, the starting level, the Novice loadout's gear, what it is drawn with, abilities and health, the stages of an ability's taps and charge levels, the spell groups and stack groups of the spells that last on a unit, whether an ability's caster may be dead (Spell4.spell4ConditionsIdCaster), the training creatures' rows, what each spell strikes, the hit rule's formulas and bases, and the prerequisites that gate a spell's resource gains and a creature attack's effects"
}

/// Runs a function of this module in a fresh node, which must return.
fn in_a_fresh_node(function: String) -> Nil {
  fresh_node.must_return(module: "server_table_test", function:)
}

/// Loads a folder holding only the planted files of the server's tables, with
/// the server's own load, and reads the appearance index the load built.
pub fn planted_load() -> Nil {
  use folder <- planted_table.in_folder(character_tables.files())
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
    as "CharacterCustomization row 2: an Exile human male with labels 22 = 1 and 2 = 1 shows display 135 in slot 25, from the index the load built"
  table_store.unload(tables)
}

pub fn the_servers_load_reads_the_files_of_its_list_and_builds_the_appearance_index_test() -> Nil {
  use <- owned_test.run(60_000)
  in_a_fresh_node("planted_load")
}

/// Loads the planted files of the server's tables except that
/// CustomizationParameterMap names a CustomizationParameter row the planted
/// table lacks.
pub fn missing_parameter_load() -> Nil {
  let files =
    list.key_set(
      character_tables.files(),
      "CustomizationParameterMap",
      character_tables.map_file_naming(parameter_id: 999_999).1,
    )
  use folder <- planted_table.in_folder(files)
  assert server_table.load(from: folder)
    == Error(table_store.RowMissing(
      from_table: "CustomizationParameterMap",
      column: "customizationParameterId",
      to_table: "CustomizationParameter",
      id: 999_999,
    ))
    as "the server's load fails on a map that names a CustomizationParameter row the table lacks, naming it"
}

pub fn the_servers_load_fails_on_a_map_naming_a_missing_parameter_row_test() -> Nil {
  use <- owned_test.run(60_000)
  in_a_fresh_node("missing_parameter_load")
}
