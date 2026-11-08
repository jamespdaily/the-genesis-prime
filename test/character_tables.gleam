//// The shared character tables, and the planted tables of the creature and
//// content tests, which run where the client's files are absent.
////
//// - `shared()` is the client's committed rows (`fixture_tables`): a character's
////   look, start place, zones, chat channels, levels and Novice loadout all come
////   from them, and the tests read their expected values from the same rows
////   (`start_rows`, `row_10_look`, `exile_circle_centre`).
//// - `files()` is the planted folder the content load reads: the client's rows of
////   WorldLocation2, WorldZone, ChatChannel, GameFormula and XpPerLevel
////   (`fixture_tables.file`), the creature, CharacterCreation, customization, label,
////   parameter and map rows planted here, and the Novice gear of `novice_tables`.
////   It holds no spell rows of the Novice loadout: a test that casts reads
////   `shared()`.
//// - Gap: the spell trees and creature rows of `content_tables` are planted, not
////   the client's (the creature-spawn step of issue 326, T3c).
//// - Bone counts: opcode.0x25b.counts gives 46 bone values for race 1, sex 1
////   and 48 for race 1, sex 0. The planted maps are that many rows of one
////   parameter that sets one part; the client's rows hold the real parameters.

import character_support
import database_support
import fixture_tables
import genesis_prime/game/start_place.{type Facing, type Place, Facing}
import genesis_prime/message/float32
import genesis_prime/store.{type LookEntry, LookEntry} as _
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
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/creature2_resist
import genesis_prime/table/creature2_tier
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/faction2
import genesis_prime/table/faction2_relationship
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  CharacterCustomizationId, CharacterCustomizationLabelId, WorldLocation2Id,
}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/requirement
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/path_mission
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite
import genesis_prime/table/unit_property2
import genesis_prime/table/world
import genesis_prime/table/world_location2
import genesis_prime/table/world_zone
import genesis_prime/table/xp_per_level
import gleam/int
import gleam/list
import novice_tables
import place_support
import planted_table.{type Cell, Boolean, Float, Integer}
import spell_tables

/// The look of the client's CharacterCustomization row 10 (race 1, sex 0): the
/// row's two labels with their values, label 2 = 1 and label 21 = 2, by label.
pub fn row_10_look() -> List(LookEntry) {
  let assert Ok(row) =
    character_customization.get(
      tables: shared(),
      id: CharacterCustomizationId(10),
    )
    as "the client's CharacterCustomization holds row 10"
  [
    #(row.character_customization_label_id00, row.value00),
    #(row.character_customization_label_id01, row.value01),
  ]
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
  |> list.map(fn(entry) {
    LookEntry(label: CharacterCustomizationLabelId(entry.0), value: entry.1)
  })
}

/// The centre of the Exile objective circle, WorldLocation2 51739, read from the
/// client's row.
pub fn exile_circle_centre() -> #(Float, Float, Float) {
  let assert Ok(row) =
    world_location2.get(tables: shared(), id: WorldLocation2Id(51_739))
    as "the client's WorldLocation2 holds the Exile objective circle's row"
  #(row.position0, row.position1, row.position2)
}

/// The client's committed rows loaded as the server's tables, stored once per
/// test run (`fixture_tables.shared`).
pub fn shared() -> store.Tables {
  fixture_tables.shared()
}

/// The planted tables with the Engineer's Volatility rows: the hidden spell and the
/// damage of Pulse Blast's damage spell, the base of `content_tables`.
fn planted_with_volatility() -> store.Tables {
  let trees =
    novice_tables.spell_tree_files_of(
      rows: spell_tables.planted_rows_with_volatility(),
      creature_attack: True,
    )
  let names = list.map(trees, fn(file) { file.0 })
  let prerequisites =
    spell_tables.sorted_by_id(list.append(
      spell_tables.planted_rows_with_volatility().prerequisites,
      prerequisite_rows(),
    ))
  load_files(list.append(
    list.map(
      list.filter(files(), fn(file) { !list.contains(names, file.0) }),
      fn(file) {
        case file.0 == prerequisite.schema.file {
          True -> planted_table.file(prerequisite.schema, prerequisites)
          False -> file
        }
      },
    ),
    trees,
  ))
}

/// The WorldLocation2 rows of the two objective circles the training creatures
/// stand in: 51739 (Exile) and 52898 (Dominion), radius 55, in World 3460,
/// WorldZone 5967, at the client's own centres (`Quest2.10518`, `Quest2.10524`).
pub const circle_ids = [51_739, 52_898]

/// The planted files of the creatures the spawns stand: each row is the client's
/// own in the columns the spawns read (`the_planted_creature_rows_...` compares
/// the spawns built from them with the real ones).
fn creature_files() -> List(#(String, BitArray)) {
  [
    planted_table.file(creature2.schema, [
      creature_row(
        id: 73_464,
        arche_type: 1,
        group: 28_793,
        faction: 1441,
        changes: [],
      ),
      creature_row(
        id: 73_465,
        arche_type: 10,
        group: 28_431,
        faction: 1442,
        changes: [],
      ),
    ]),
    planted_table.file(creature2_arche_type.schema, [
      multiplier_row(
        schema: creature2_arche_type.schema,
        id: 1,
        value: 1.0,
        deflect: 1.0,
        attack: Attack(stats: 1.0, crit: 1.0, severity: 1.0),
      ),
      multiplier_row(
        schema: creature2_arche_type.schema,
        id: 10,
        value: 0.9599999785423279,
        deflect: 1.0,
        attack: Attack(stats: 1.059999942779541, crit: 1.0, severity: 1.0),
      ),
    ]),
    planted_table.file(creature2_difficulty.schema, [
      multiplier_row(
        schema: creature2_difficulty.schema,
        id: 1,
        value: 0.3869999945163727,
        deflect: 0.3199999928474426,
        attack: Attack(
          stats: 0.6800000071525574,
          crit: 0.3199999928474426,
          severity: 1.0,
        ),
      ),
    ]),
    planted_table.file(creature2_tier.schema, [
      multiplier_row(
        schema: creature2_tier.schema,
        id: 1,
        value: 1.0,
        deflect: 1.0,
        attack: Attack(stats: 1.0, crit: 1.0, severity: 0.8500000238418579),
      ),
    ]),
    planted_table.file(creature2_resist.schema, [
      planted_table.row(creature2_resist.schema, [#("ID", Integer(1))]),
    ]),
    planted_table.file(creature2_display_info.schema, [
      planted_table.row(creature2_display_info.schema, [
        #("ID", Integer(26_565)),
        #("hitRadius", Float(3.0)),
        #("runLand", Float(10.0)),
      ]),
      planted_table.row(creature2_display_info.schema, [
        #("ID", Integer(26_578)),
        #("hitRadius", Float(2.0)),
        #("runLand", Float(10.0)),
      ]),
    ]),
    planted_table.file(creature2_display_group_entry.schema, [
      group_entry_row(id: 27_192, group: 28_793, display: 26_565),
      group_entry_row(id: 27_216, group: 28_431, display: 26_578),
    ]),
    planted_table.file(creature2_override_properties.schema, [
      override_row(id: 25_965, creature: 73_464, property: 40, value: 1.0),
      override_row(id: 26_167, creature: 73_464, property: 42, value: 0.0),
      override_row(id: 25_967, creature: 73_465, property: 40, value: 1.0),
      override_row(id: 26_168, creature: 73_465, property: 42, value: 0.0),
    ]),
    planted_table.file(creature2_outfit_group_entry.schema, []),
    planted_table.file(instance_portal.schema, []),
    planted_table.file(path_mission.schema, []),
  ]
}

pub fn creature_row(
  id id: Int,
  arche_type arche_type: Int,
  group group: Int,
  faction faction: Int,
  changes changes: List(#(String, Cell)),
) -> List(Cell) {
  let base = [
    #("ID", Integer(id)),
    #("CreationTypeEnum", Integer(0)),
    #("creature2DifficultyId", Integer(1)),
    #("creature2ArcheTypeId", Integer(arche_type)),
    #("creature2TierId", Integer(1)),
    #("creature2DisplayGroupId", Integer(group)),
    #("creature2ResistId", Integer(1)),
    #("modelScale", Float(1.0)),
    #("factionId", Integer(faction)),
    #("minLevel", Integer(1)),
    #("maxLevel", Integer(1)),
  ]
  planted_table.row(creature2.schema, list.append(changes, base))
}

/// The multipliers of the properties a creature's attack reads, each the client's
/// row's: Strength and AssaultRating (0 and 35, `stats`), BaseCritChance and
/// BaseAvoidReduceChance (102 and 104, `crit`) and CriticalHitSeverityMultiplier
/// (127, `severity`); MoveSpeedMultiplier (100) is 1.0 in every row they read.
type Attack {
  Attack(stats: Float, crit: Float, severity: Float)
}

/// A multiplier row: the one for Base Health, the one for BaseAvoidChance (101), the
/// only other property the Virtual Battle Beast's defence has (the client's rows give
/// the others 0 products, `Creature2.73464.crit_deflect_glance`), and the ones its
/// attack reads.
fn multiplier_row(
  schema schema: tbl_file.Schema,
  id id: Int,
  value value: Float,
  deflect deflect: Float,
  attack attack: Attack,
) -> List(Cell) {
  planted_table.row(schema, [
    #("ID", Integer(id)),
    #("unitPropertyMultiplier000", Float(attack.stats)),
    #("unitPropertyMultiplier007", Float(value)),
    #("unitPropertyMultiplier035", Float(attack.stats)),
    #("unitPropertyMultiplier100", Float(1.0)),
    #("unitPropertyMultiplier101", Float(deflect)),
    #("unitPropertyMultiplier102", Float(attack.crit)),
    #("unitPropertyMultiplier104", Float(attack.crit)),
    #("unitPropertyMultiplier127", Float(attack.severity)),
  ])
}

pub fn group_entry_row(
  id id: Int,
  group group: Int,
  display display: Int,
) -> List(Cell) {
  planted_table.row(creature2_display_group_entry.schema, [
    #("id", Integer(id)),
    #("creature2DisplayGroupId", Integer(group)),
    #("creature2DisplayInfoId", Integer(display)),
    #("weight", Integer(1)),
  ])
}

pub fn override_row(
  id id: Int,
  creature creature: Int,
  property property: Int,
  value value: Float,
) -> List(Cell) {
  planted_table.row(creature2_override_properties.schema, [
    #("ID", Integer(id)),
    #("creature2Id", Integer(creature)),
    #("unitPropertyIndex", Integer(property)),
    #("unitPropertyValue", Float(value)),
  ])
}

/// The planted files of the server's tables, each by its file name: one file
/// for every entry of `server_table.entries`, so a load of the server's list
/// from a folder of them reads every file and meets every requirement.
pub fn files() -> List(#(String, BitArray)) {
  list.append(creature_files(), [
    planted_table.file(character_creation.schema, creation_rows()),
    planted_table.file(character_customization.schema, customization_rows()),
    planted_table.file(character_customization_label.schema, label_rows()),
    planted_table.file(customization_parameter.schema, parameter_rows()),
    planted_table.file(customization_parameter_map.schema, map_rows()),
    fixture_tables.file(world_location2.schema),
    fixture_tables.file(world_zone.schema),
    fixture_tables.file(chat_channel.schema),
    fixture_tables.file(game_formula.schema),
    fixture_tables.file(xp_per_level.schema),
    planted_table.file(unit_property2.schema, spell_tables.unit_property_rows()),
    planted_table.file(
      prerequisite.schema,
      spell_tables.sorted_by_id(list.append(
        fixture_tables.committed_rows(prerequisite.schema),
        prerequisite_rows(),
      )),
    ),
    fixture_tables.file(positional_requirement.schema),
    ..novice_tables.files()
  ])
}

/// The planted files with the file of `schema` holding these rows in place of the
/// planted ones, for a test of a rule that reads that table.
pub fn files_replacing(
  schema schema: tbl_file.Schema,
  rows rows: List(List(Cell)),
) -> List(#(String, BitArray)) {
  list.map(files(), fn(file) {
    case file.0 == schema.file {
      True -> planted_table.file(schema, rows)
      False -> file
    }
  })
}

/// The planted files with the Virtual Battle Beast's Creature2 row (73464)
/// changed in the columns `changes` name, each a column of the client's table and
/// the cell it holds instead.
pub fn files_with_beast_changed(
  changes changes: List(#(String, Cell)),
) -> List(#(String, BitArray)) {
  list.map(files(), fn(file) {
    case file.0 == creature2.schema.file {
      True ->
        planted_table.file(creature2.schema, [
          creature_row(
            id: 73_464,
            arche_type: 1,
            group: 28_793,
            faction: 1441,
            changes:,
          ),
          creature_row(
            id: 73_465,
            arche_type: 10,
            group: 28_431,
            faction: 1442,
            changes: [],
          ),
        ])
      False -> file
    }
  })
}

/// The planted file of CustomizationParameterMap with one map, of race 1 and
/// sex 0, that names this CustomizationParameter id.
pub fn map_file_naming(parameter_id parameter_id: Int) -> #(String, BitArray) {
  planted_table.file(customization_parameter_map.schema, [
    map(id: 1, sex: 0, parameter_id:),
  ])
}

/// The Faction2 rows the planted factions walk: id and parent, as the client's.
const faction_parents = [
  #(164, 0),
  #(165, 0),
  #(166, 165),
  #(167, 165),
  #(168, 164),
  #(174, 168),
  #(177, 168),
  #(189, 177),
  #(219, 0),
  #(1441, 164),
  #(1442, 164),
]

/// The Faction2Relationship rows among them, as id, factionId0, factionId1 and
/// factionLevel, the client's: Dominion 166 and Exile 167 are level 0 (Hostile)
/// to each other, 189 is level 0 to 165, 219 is level 10 to 165 and 164, 1441 is
/// level 0 to Exile and 10 to Dominion, 1442 level 0 to Dominion and 10 to Exile.
const faction_relationships = [
  #(684, 166, 167, 0),
  #(691, 189, 165, 0),
  #(726, 219, 165, 10),
  #(944, 219, 164, 10),
  #(2943, 1441, 167, 0),
  #(2944, 1441, 166, 10),
  #(2945, 1441, 174, 0),
  #(2946, 1442, 166, 0),
  #(2947, 1442, 167, 10),
  #(2948, 1442, 174, 0),
]

/// The Worlds the tests' maps run in, each with the id column only.
const content_worlds = [22, 51, 426, 870, 990, 1061, 1387, 3460, 3461, 6009]

/// The planted files of the tables only the content load reads
/// (`server_table.content_entries`), each by its file name.
pub fn content_files() -> List(#(String, BitArray)) {
  [
    planted_table.file(
      faction2.schema,
      list.map(faction_parents, fn(faction) {
        planted_table.row(faction2.schema, [
          #("ID", Integer(faction.0)),
          #("faction2IdParent", Integer(faction.1)),
        ])
      }),
    ),
    planted_table.file(
      faction2_relationship.schema,
      list.map(faction_relationships, fn(relationship) {
        planted_table.row(faction2_relationship.schema, [
          #("ID", Integer(relationship.0)),
          #("factionId0", Integer(relationship.1)),
          #("factionId1", Integer(relationship.2)),
          #("factionLevel", Integer(relationship.3)),
        ])
      }),
    ),
    planted_table.file(creature2_outfit_info.schema, []),
    planted_table.file(
      world.schema,
      list.map(content_worlds, fn(id) {
        planted_table.row(world.schema, [#("ID", Integer(id))])
      }),
    ),
  ]
}

/// The client's Prerequisite rows of the creature attack's effects
/// (`Spell4Effects.184741`): 30526, the caster's difficulty (type 179) at most 6
/// (comparison 6), and 30527, at least 7 (comparison 4).
pub fn prerequisite_rows() -> List(List(Cell)) {
  list.map([#(30_526, 6, 6), #(30_527, 4, 7)], fn(condition) {
    planted_table.row(prerequisite.schema, [
      #("ID", Integer(condition.0)),
      #("prerequisiteTypeId0", Integer(179)),
      #("prerequisiteComparisonId0", Integer(condition.1)),
      #("objectId0", Integer(condition.2)),
    ])
  })
}

/// The tables only the content load reads, loaded once from the planted files
/// beside the planted tables with the Engineer's Volatility rows
/// (`planted_with_volatility`): the content load reads the creature tables
/// where they are, and the spell trees the server's Proxy of migration 0018 is selected
/// from (Pulse Blast's two goes and the hidden 42148). Stored once and never erased,
/// as `shared` is, and the only planted load that is.
pub fn content_tables() -> store.Tables {
  database_support.once("character_content_tables", fn() {
    use folder <- planted_table.in_folder(content_files())
    let assert Ok(tables) =
      server_table.load_content_tables(
        over: planted_with_volatility(),
        from: folder,
      )
      as "the planted files load as the content load's tables"
    store.store_under(tables:)
  })
}

/// The server's tables read from these planted files on the caller's heap, with
/// the server's requirements and derivations. Nothing is stored.
fn read_files(files: List(#(String, BitArray))) -> store.Tables {
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) = server_table.read(from: folder)
    as "the planted character tables load as the server's tables do"
  tables
}

/// The plain planted tables (`files`), read on the caller's heap and never stored:
/// the tables `novice_tables_test` compares with the client's, and the tables the
/// variants edit.
pub fn plain() -> store.Tables {
  read_files(files())
}

/// The plain tables edited into the tables of these planted files, on the
/// caller's heap: each file that differs from the plain files replaces its table,
/// and the server's requirements and derivations run on the result. A file no
/// entry of the server reads is a mistake of the caller.
fn load_files(wanted: List(#(String, BitArray))) -> store.Tables {
  let plain_files = files()
  let entries = server_table.entries()
  let edits =
    list.filter_map(wanted, fn(file) {
      case list.key_find(plain_files, file.0) == Ok(file.1) {
        True -> Error(Nil)
        False -> {
          let assert Ok(entry) =
            list.find(entries, fn(entry) { store.file(entry) == file.0 })
            as "a planted file is a file of one of the server's tables"
          Ok(store.replace_rows(entry, bytes: file.1))
        }
      }
    })
  let assert Ok(tables) =
    store.edit(
      tables: plain(),
      with: edits,
      requirements: requirement.all(),
      derivations: derivation.all(),
    )
    as "the planted character tables load as the server's tables do"
  tables
}

/// A CharacterCreation row with the columns the server reads.
fn creation(
  id id: Int,
  class_id class_id: Int,
  race_id race_id: Int,
  sex sex: Int,
  faction_id faction_id: Int,
  costume_only costume_only: Bool,
  enabled enabled: Bool,
  start start: Int,
  xp xp: Int,
  currency_type currency_type: Int,
  currency_amount currency_amount: Int,
  entitlement entitlement: Int,
) -> List(Cell) {
  planted_table.row(character_creation.schema, [
    #("ID", Integer(id)),
    #("classId", Integer(class_id)),
    #("raceId", Integer(race_id)),
    #("sex", Integer(sex)),
    #("factionId", Integer(faction_id)),
    #("costumeOnly", Boolean(costume_only)),
    #("enabled", Boolean(enabled)),
    #("characterCreationStartEnum", Integer(start)),
    #("xp", Integer(xp)),
    #("accountCurrencyTypeIdCost", Integer(currency_type)),
    #("accountCurrencyAmountCost", Integer(currency_amount)),
    #("entitlementIdRequired", Integer(entitlement)),
  ])
}

/// The planted CharacterCreation rows, each with its ID cell first.
pub fn creation_rows() -> List(List(Cell)) {
  [
    // 21: a disabled Arkship row (start 0).
    creation(
      id: 21,
      class_id: 1,
      race_id: 1,
      sex: 1,
      faction_id: 167,
      costume_only: False,
      enabled: False,
      start: 0,
      xp: 0,
      currency_type: 0,
      currency_amount: 0,
      entitlement: 0,
    ),
    // 338 and 339: Nexus rows, race 1, sex 1 and sex 0.
    creation(
      id: 338,
      class_id: 1,
      race_id: 1,
      sex: 1,
      faction_id: 167,
      costume_only: False,
      enabled: True,
      start: 3,
      xp: 1710,
      currency_type: 0,
      currency_amount: 0,
      entitlement: 0,
    ),
    creation(
      id: 339,
      class_id: 1,
      race_id: 1,
      sex: 0,
      faction_id: 167,
      costume_only: False,
      enabled: True,
      start: 3,
      xp: 1710,
      currency_type: 0,
      currency_amount: 0,
      entitlement: 0,
    ),
    // 359: a Nexus row, class 1, race 1 (Cassian), sex 0, faction 166.
    creation(
      id: 359,
      class_id: 1,
      race_id: 1,
      sex: 0,
      faction_id: 166,
      costume_only: False,
      enabled: True,
      start: 3,
      xp: 1710,
      currency_type: 0,
      currency_amount: 0,
      entitlement: 0,
    ),
    // 530: costume only, class 0.
    creation(
      id: 530,
      class_id: 0,
      race_id: 0,
      sex: 0,
      faction_id: 167,
      costume_only: True,
      enabled: True,
      start: 99,
      xp: 0,
      currency_type: 0,
      currency_amount: 0,
      entitlement: 0,
    ),
    // 536: a Nexus row needing entitlement 61.
    creation(
      id: 536,
      class_id: 1,
      race_id: 13,
      sex: 0,
      faction_id: 166,
      costume_only: False,
      enabled: True,
      start: 3,
      xp: 1710,
      currency_type: 0,
      currency_amount: 0,
      entitlement: 61,
    ),
    // 539: a Level50 row costing 1 of account currency 13.
    creation(
      id: 539,
      class_id: 1,
      race_id: 1,
      sex: 1,
      faction_id: 167,
      costume_only: False,
      enabled: True,
      start: 5,
      xp: 26_360_090,
      currency_type: 13,
      currency_amount: 1,
      entitlement: 0,
    ),
    ..novice_tables.creation_rows()
  ]
}

/// A CharacterCustomization row of race 1, slot 25, flags 2.
fn customization(
  id id: Int,
  sex sex: Int,
  display display: Int,
  first first: #(Int, Int),
  second second: #(Int, Int),
) -> List(Cell) {
  planted_table.row(character_customization.schema, [
    #("ID", Integer(id)),
    #("raceId", Integer(1)),
    #("gender", Integer(sex)),
    #("itemSlotId", Integer(25)),
    #("itemDisplayId", Integer(display)),
    #("flags", Integer(2)),
    #("characterCustomizationLabelId00", Integer(first.0)),
    #("value00", Integer(first.1)),
    #("characterCustomizationLabelId01", Integer(second.0)),
    #("value01", Integer(second.1)),
  ])
}

fn customization_rows() -> List(List(Cell)) {
  [
    // Sex 0: labels 22 = 1 and 2 = 1 (the Exile face), 22 = 2 and 2 = 1, and
    // 21 = 2 and 2 = 1 (the Dominion face). Sex 1: 22 = 1 and 2 = 1, and
    // 22 = 2 and 2 = 1.
    customization(id: 2, sex: 0, display: 135, first: #(22, 1), second: #(2, 1)),
    customization(id: 9, sex: 0, display: 136, first: #(22, 2), second: #(2, 1)),
    customization(id: 10, sex: 0, display: 137, first: #(21, 2), second: #(2, 1)),
    customization(id: 603, sex: 1, display: 311, first: #(22, 1), second: #(
      2,
      1,
    )),
    customization(id: 604, sex: 1, display: 312, first: #(22, 2), second: #(
      2,
      1,
    )),
  ]
}

fn label(id id: Int, faction faction: Int) -> List(Cell) {
  planted_table.row(character_customization_label.schema, [
    #("ID", Integer(id)),
    #("faction2Id", Integer(faction)),
  ])
}

fn label_rows() -> List(List(Cell)) {
  // Label 2 is for every faction, 21 for faction 166 and 22 for faction 167;
  // 26 and 27 set the race, for factions 166 and 167, and no look holds them.
  [
    label(id: 2, faction: 0),
    label(id: 21, faction: 166),
    label(id: 22, faction: 167),
    label(id: 26, faction: 166),
    label(id: 27, faction: 167),
  ]
}

fn parameter_rows() -> List(List(Cell)) {
  [
    planted_table.row(customization_parameter.schema, [
      #("ID", Integer(1)),
      #("sclX", Integer(1)),
    ]),
  ]
}

/// 46 maps for race 1, sex 1 and 48 for race 1, sex 0, each of parameter 1.
fn map_rows() -> List(List(Cell)) {
  list.append(
    list.map(character_support.numbers(46), fn(id) {
      map(id:, sex: 1, parameter_id: 1)
    }),
    list.map(character_support.numbers(48), fn(index) {
      map(id: index + 46, sex: 0, parameter_id: 1)
    }),
  )
}

/// A CustomizationParameterMap row of race 1 and this sex that names this
/// CustomizationParameter id.
fn map(id id: Int, sex sex: Int, parameter_id parameter_id: Int) -> List(Cell) {
  planted_table.row(customization_parameter_map.schema, [
    #("ID", Integer(id)),
    #("raceId", Integer(1)),
    #("genderEnum", Integer(sex)),
    #("customizationParameterId", Integer(parameter_id)),
  ])
}

/// A start place's WorldLocation2 row, read from the client's rows: its id, the
/// place it stands at (world, zone and position, facing as a character that has
/// never turned does), its facing quaternion x, y, z, w (facing0 to facing3),
/// the 32 bits of the yaw, pitch and roll the client's QuaternionToEulerAngles
/// (0x1401b2fe0) makes of it, from the emulator, and the fact record that names
/// the row. For a turn about y alone, m21 = 2(y*z - w*x) is a zero and the pitch
/// asin(-m21) is -0.0 (0x80000000), except where y < 0 and w > 0 (8223): m21 is
/// -0 and the pitch +0.0.
pub type StartRow {
  StartRow(
    id: Int,
    place: Place,
    quaternion: #(Float, Float, Float, Float),
    facing_bits: #(Int, Int, Int),
    record: String,
  )
}

/// The start places' ids with what the emulator returned for each facing and
/// the record that names it: 51596 for the Novice start, 42074 and 41641 for
/// the Exile Veteran start, 42148 and 8223 for the Dominion Veteran start.
const start_facings = [
  #(42_074, #(0xC021E1A7, 0x80000000, 0), "Quest2.10528.links"),
  #(41_641, #(0x4021F773, 0x80000000, 0), "Quest2.10528.links"),
  #(42_148, #(0xC0490FDA, 0x80000000, 0), "Quest2.10530.links"),
  #(8223, #(0xBFD09BA3, 0, 0), "Quest2.10530.links"),
  #(51_596, #(0xC03017E2, 0x80000000, 0), "Quest2.10513 (a guess)"),
]

/// The start places' rows, each read from the client's WorldLocation2 row.
pub fn start_rows() -> List(StartRow) {
  list.map(start_facings, fn(facing) {
    let #(id, facing_bits, record) = facing
    let assert Ok(row) =
      world_location2.get(tables: shared(), id: WorldLocation2Id(id))
      as "the client's WorldLocation2 holds the start place's row"
    StartRow(
      id:,
      place: place_support.at(
        world_id: row.world_id,
        world_zone_id: row.world_zone_id,
        x: row.position0,
        y: row.position1,
        z: row.position2,
      ),
      quaternion: #(row.facing0, row.facing1, row.facing2, row.facing3),
      facing_bits:,
      record:,
    )
  })
}

/// The start row with this id.
pub fn start_row(id: Int) -> StartRow {
  let assert Ok(row) = list.find(start_rows(), fn(row) { row.id == id })
    as "the test names a start place's row"
  row
}

/// The place of the Novice start, WorldLocation2 row 51596: its world, zone and
/// position, facing as the client's conversion gives the row's facing, from the
/// bits the emulator returned for it (record 0x1401b2fe0).
pub fn novice_start_place() -> Place {
  let row = start_row(51_596)
  start_place.turned(
    row.place,
    Facing(
      yaw: float_of_bits(row.facing_bits.0),
      pitch: float_of_bits(row.facing_bits.1),
      roll: float_of_bits(row.facing_bits.2),
    ),
  )
}

/// The 32-bit float with these bits.
fn float_of_bits(number: Int) -> Float {
  let assert Ok(bits) = float32.bits(number) as "the bits are 32 bits"
  let assert Ok(value) = float32.value(bits) as "the bits are a finite float"
  value
}

/// The 32 bits of a facing's yaw, pitch and roll.
pub fn facing_bits(facing: Facing) -> #(Int, Int, Int) {
  #(
    float32.to_bits(facing.yaw),
    float32.to_bits(facing.pitch),
    float32.to_bits(facing.roll),
  )
}

/// Whether the place is the row's: the row's world, zone and position, facing
/// as the client's conversion gives the row's facing, to the bit.
pub fn is_the_place_of(place place: Place, row row: StartRow) -> Bool {
  start_place.turned(place, start_place.unturned) == row.place
  && facing_bits(start_place.facing(place)) == row.facing_bits
}
