//// A small set of the client's tables for the tests of the game rule, character
//// select and creating a character, which run where the client's files are
//// absent. Each row is a row of the client's own tables with the id and the
//// columns the server reads (`character_tables_test` compares each with the
//// real row where the client is present); every other column is 0.
////
//// - CharacterCreation rows 21, 338, 339, 359, 530, 536 and 539, with their xp, and
////   the twelve Novice rows of `novice_tables` (466 and eleven more), with their
////   items.
//// - The Novice gear's tables (`novice_tables`): Item2, Item2Type, Item2Family,
////   Item2Category, ItemSlot, CreatureLevel, Spell4 and SpellLevel, and the
////   GameFormula rows the item formulas read.
//// - GameFormula row 145 (its dataint0, the highest level) and XpPerLevel
////   records 1 to 51 with their minXpForLevel, which GetLevelForExperience
////   0x140029820 reads.
//// - CharacterCustomization rows 2, 9 and 10 (race 1, sex 0) and 603 and 604
////   (race 1, sex 1) and the labels they use, 2, 21 and 22, with labels 26 and
////   27 (CharacterCustomizationLabel), which no row holds.
//// - WorldLocation2 rows 51596, 42074, 41641, 42148 and 8223,
////   the start places (genesis_prime/game/start_place), with the world, zone,
////   position and facing quaternion of the client's row, and rows 51739 and
////   52898, the objective circles the creatures stand in (radius, position,
////   world and zone).
//// - The training creatures' rows: Creature2 73464 and 73465 with the rows their
////   values come from (ArcheType 1 and 10, Difficulty 1, Tier 1, CreatureLevel 1,
////   Resist 1, the display groups 28793 and 28431 with their entries and
////   displays 26565 and 26578, and the Stamina and Armor overrides), in the
////   columns the spawns read (genesis_prime/world_map/spawn).
//// - Bone counts: opcode.0x25b.counts gives 46 bone values for race 1, sex 1
////   and 48 for race 1, sex 0. The planted maps are that many rows of one
////   parameter that sets one part, which carry those counts; the real
////   parameters are read by the real-table tests.

import character_support
import database_support
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
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/creature2_resist
import genesis_prime/table/creature2_tier
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/game_formula
import genesis_prime/table/id.{CharacterCustomizationLabelId}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/world_location2
import genesis_prime/table/world_zone
import genesis_prime/table/xp_per_level
import gleam/erlang/reference
import gleam/int
import gleam/list
import novice_tables
import place_support
import planted_table.{type Cell, Boolean, Float, Integer}

/// The look of the planted CharacterCustomization row 10 (race 1, sex 0,
/// faction 166): label 2 = 1 and label 21 = 2, which show display 137 on
/// slot 25.
pub fn row_10_look() -> List(LookEntry) {
  [
    LookEntry(label: CharacterCustomizationLabelId(2), value: 1),
    LookEntry(label: CharacterCustomizationLabelId(21), value: 2),
  ]
}

/// The planted tables, loaded once per test run under a key of their own and
/// never unloaded, as `client_tables.shared` does for the real ones.
pub fn shared() -> store.Tables {
  database_support.once("character_tables", load)
}

/// The planted tables with the Novice start's WorldLocation2 row (51596) in
/// World 0, which is no World row, in place of World 3460. Loaded once under a
/// key of its own.
pub fn shared_with_novice_start_in_world_0() -> store.Tables {
  database_support.once("character_tables_novice_world_0", fn() {
    let rows =
      list.map(start_rows(), fn(row) {
        case row.id {
          51_596 ->
            location(
              id: 51_596,
              world: 0,
              zone: 0,
              position: #(0.0, 0.0, 0.0),
              quaternion: row.quaternion,
            )
          _ -> planted_start_row(row)
        }
      })
      |> list.append(circle_rows())
    load_files(
      list.map(files(), fn(file) {
        case file.0 == world_location2.schema.file {
          True -> planted_table.file(world_location2.schema, rows)
          False -> file
        }
      }),
    )
  })
}

/// The WorldLocation2 rows of the two objective circles the training creatures
/// stand in: 51739 (Exile) and 52898 (Dominion), radius 55, in World 3460,
/// WorldZone 5967, at the client's own centres (`Quest2.10518`, `Quest2.10524`).
pub const circle_ids = [51_739, 52_898]

fn circle_rows() -> List(List(Cell)) {
  [
    circle(id: 51_739, position: #(
      -131.13499450683594,
      -875.2354125976562,
      333.3179931640625,
    )),
    circle(id: 52_898, position: #(
      37.852699279785156,
      -875.4901733398438,
      289.1130065917969,
    )),
  ]
}

fn circle(id id: Int, position position: #(Float, Float, Float)) -> List(Cell) {
  planted_table.row(world_location2.schema, [
    #("ID", Integer(id)),
    #("radius", Float(55.0)),
    #("position0", Float(position.0)),
    #("position1", Float(position.1)),
    #("position2", Float(position.2)),
    #("worldId", Integer(3460)),
    #("worldZoneId", Integer(5967)),
  ])
}

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
      multiplier_row(schema: creature2_arche_type.schema, id: 1, value: 1.0),
      multiplier_row(
        schema: creature2_arche_type.schema,
        id: 10,
        value: 0.9599999785423279,
      ),
    ]),
    planted_table.file(creature2_difficulty.schema, [
      multiplier_row(
        schema: creature2_difficulty.schema,
        id: 1,
        value: 0.3869999945163727,
      ),
    ]),
    planted_table.file(creature2_tier.schema, [
      multiplier_row(schema: creature2_tier.schema, id: 1, value: 1.0),
    ]),
    planted_table.file(creature2_resist.schema, [
      planted_table.row(creature2_resist.schema, [#("ID", Integer(1))]),
    ]),
    planted_table.file(creature2_display_info.schema, [
      planted_table.row(creature2_display_info.schema, [
        #("ID", Integer(26_565)),
      ]),
      planted_table.row(creature2_display_info.schema, [
        #("ID", Integer(26_578)),
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
  ]
}

fn creature_row(
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

fn multiplier_row(
  schema schema: tbl_file.Schema,
  id id: Int,
  value value: Float,
) -> List(Cell) {
  planted_table.row(schema, [
    #("ID", Integer(id)),
    #("unitPropertyMultiplier007", Float(value)),
  ])
}

fn group_entry_row(
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

fn override_row(
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
  files_with_looks(customization: customization_rows(), labels: label_rows())
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

/// The planted files with the WorldZone file holding these zones, each a pair of
/// its id and its parentZoneId, in place of `world_zones`.
pub fn files_with_zones(
  zones zones: List(#(Int, Int)),
) -> List(#(String, BitArray)) {
  list.map(files(), fn(file) {
    case file.0 == world_zone.schema.file {
      True -> world_zone_file(zones)
      False -> file
    }
  })
}

/// The planted WorldZone rows, each a pair of the row's ID and parentZoneId from
/// the client's own table (`top_zone_test` compares each with the real row): the
/// chains of the start places' zones 648, 1417, 1411, 1236 and 6009 up to their
/// top zones, 1411 and 1305 sharing the top zone 1304; the chain of zone 1755,
/// the deepest, 7 parents above it, to its top zone 248; and zone 147, whose
/// parent 1132 has no row.
pub fn world_zones() -> List(#(Int, Int)) {
  [
    #(648, 35),
    #(35, 0),
    #(1417, 1414),
    #(1414, 0),
    #(1411, 1305),
    #(1305, 1304),
    #(1304, 0),
    #(1236, 623),
    #(623, 622),
    #(622, 0),
    #(6009, 4962),
    #(4962, 4961),
    #(4961, 0),
    #(1755, 378),
    #(378, 1777),
    #(1777, 382),
    #(382, 1778),
    #(1778, 1738),
    #(1738, 1580),
    #(1580, 248),
    #(248, 0),
    #(147, 1132),
  ]
}

/// The planted ChatChannel rows: the ID, enumName and flags of the client's own
/// rows (`chat_test` compares each with the real row) for the channels the chat
/// rule tells apart: Command, System, Say, Yell, Whisper, Party, Emote, Zone,
/// Trade, Guild, Support, NPCSay, Instance and AccountWhisper.
pub fn chat_channels() -> List(#(Int, String, Int)) {
  [
    #(1, "Command", 8),
    #(2, "System", 8),
    #(4, "Say", 29),
    #(5, "Yell", 30),
    #(6, "Whisper", 12),
    #(7, "Party", 28),
    #(8, "Emote", 13),
    #(9, "Zone", 1676),
    #(11, "Trade", 1676),
    #(15, "Guild", 4),
    #(19, "Support", 268),
    #(20, "NPCSay", 24),
    #(32, "Instance", 28),
    #(34, "AccountWhisper", 44),
  ]
}

fn chat_channel_file() -> #(String, BitArray) {
  planted_table.file(
    chat_channel.schema,
    list.map(chat_channels(), fn(channel) {
      planted_table.row(chat_channel.schema, [
        #("ID", Integer(channel.0)),
        #("enumName", planted_table.Text(channel.1)),
        #("flags", Integer(channel.2)),
      ])
    }),
  )
}

fn world_zone_file(zones: List(#(Int, Int))) -> #(String, BitArray) {
  planted_table.file(
    world_zone.schema,
    list.map(zones, fn(zone) {
      planted_table.row(world_zone.schema, [
        #("ID", Integer(zone.0)),
        #("parentZoneId", Integer(zone.1)),
      ])
    }),
  )
}

/// The planted tables with a look that has `count` labels: labels 1 to
/// `count`, each for every faction and each held at the value 1 by one row of
/// race 1, sex 1, in place of the planted look rows. Loaded once per count
/// under a key of its own.
pub fn shared_with_labels(count count: Int) -> store.Tables {
  database_support.once(
    "character_tables_labels_" <> int.to_string(count),
    fn() {
      let ids = character_support.numbers(count)
      load_files(files_with_looks(
        customization: list.map(ids, fn(id) {
          customization(
            id: 1000 + id,
            sex: 1,
            display: 2000 + id,
            first: #(id, 1),
            second: #(0, 0),
          )
        }),
        labels: list.map(ids, fn(id) { label(id:, faction: 0) }),
      ))
    },
  )
}

fn files_with_looks(
  customization customization: List(List(Cell)),
  labels labels: List(List(Cell)),
) -> List(#(String, BitArray)) {
  list.append(creature_files(), [
    planted_table.file(character_creation.schema, creation_rows()),
    planted_table.file(character_customization.schema, customization),
    planted_table.file(character_customization_label.schema, labels),
    planted_table.file(customization_parameter.schema, parameter_rows()),
    planted_table.file(customization_parameter_map.schema, map_rows()),
    planted_table.file(
      world_location2.schema,
      list.append(planted_start_rows(), circle_rows()),
    ),
    world_zone_file(world_zones()),
    chat_channel_file(),
    planted_table.file(
      game_formula.schema,
      list.append(
        game_formula_rows(ids: [highest_level_formula], highest: 50),
        list.map(novice_tables.formulas(), novice_tables.game_formula_row),
      ),
    ),
    planted_table.file(
      xp_per_level.schema,
      xp_per_level_rows(min_xp_for_level()),
    ),
    ..novice_tables.files()
  ])
}

/// The planted file of CustomizationParameterMap with one map, of race 1 and
/// sex 0, that names this CustomizationParameter id.
pub fn map_file_naming(parameter_id parameter_id: Int) -> #(String, BitArray) {
  planted_table.file(customization_parameter_map.schema, [
    map(id: 1, sex: 0, parameter_id:),
  ])
}

fn load() -> store.Tables {
  load_files(files())
}

fn load_files(files: List(#(String, BitArray))) -> store.Tables {
  use folder <- planted_table.in_folder(files)
  let assert Ok(tables) =
    server_table.load_under(under: reference.new(), from: folder)
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

/// A WorldLocation2 row with the columns the server reads.
fn location(
  id id: Int,
  world world: Int,
  zone zone: Int,
  position position: #(Float, Float, Float),
  quaternion quaternion: #(Float, Float, Float, Float),
) -> List(Cell) {
  planted_table.row(world_location2.schema, [
    #("ID", Integer(id)),
    #("position0", Float(position.0)),
    #("position1", Float(position.1)),
    #("position2", Float(position.2)),
    #("facing0", Float(quaternion.0)),
    #("facing1", Float(quaternion.1)),
    #("facing2", Float(quaternion.2)),
    #("facing3", Float(quaternion.3)),
    #("worldId", Integer(world)),
    #("worldZoneId", Integer(zone)),
  ])
}

/// A start place's WorldLocation2 row as the client holds it: its id, the
/// place it stands at (world, zone and position, facing as a character that has
/// never turned does), its facing quaternion x, y, z, w (facing0 to facing3)
/// and the 32 bits of the yaw, pitch and roll the client's
/// QuaternionToEulerAngles (0x1401b2fe0) makes of it, from the emulator, and
/// the fact record that names the row. For a turn about y alone, m21 =
/// 2(y*z - w*x) is a zero and the pitch asin(-m21) is -0.0 (0x80000000), except
/// where y < 0 and w > 0 (8223): m21 is -0 and the pitch +0.0.
pub type StartRow {
  StartRow(
    id: Int,
    place: Place,
    quaternion: #(Float, Float, Float, Float),
    facing_bits: #(Int, Int, Int),
    record: String,
  )
}

/// The start places' rows: 51596 for the Novice start, 42074 and 41641 for the
/// Exile Veteran start, 42148 and 8223 for the Dominion Veteran start.
pub fn start_rows() -> List(StartRow) {
  [
    StartRow(
      id: 42_074,
      place: place_support.at(
        world_id: 426,
        world_zone_id: 648,
        x: 4098.16015625,
        y: -665.9780883789062,
        z: -5165.10009765625,
      ),
      quaternion: #(0.0, 0.9535170197486877, 0.0, -0.3013400137424469),
      facing_bits: #(0xC021E1A7, 0x80000000, 0),
      record: "Quest2.10528.links",
    ),
    StartRow(
      id: 41_641,
      place: place_support.at(
        world_id: 990,
        world_zone_id: 1417,
        x: -768.36572265625,
        y: -904.805419921875,
        z: -2275.0791015625,
      ),
      quaternion: #(0.0, 0.953717052936554, 0.0, 0.3007054626941681),
      facing_bits: #(0x4021F773, 0x80000000, 0),
      record: "Quest2.10528.links",
    ),
    StartRow(
      id: 42_148,
      place: place_support.at(
        world_id: 1387,
        world_zone_id: 1411,
        x: -3835.7451171875,
        y: -980.21728515625,
        z: -6053.263671875,
      ),
      quaternion: #(0.0, 1.0, 0.0, -4.3711395392165286e-8),
      facing_bits: #(0xC0490FDA, 0x80000000, 0),
      record: "Quest2.10530.links",
    ),
    StartRow(
      id: 8223,
      place: place_support.at(
        world_id: 870,
        world_zone_id: 1236,
        x: -8260.708984375,
        y: -995.0770263671875,
        z: -239.0409393310547,
      ),
      quaternion: #(0.0, -0.7276397347450256, 0.0, 0.6859594583511353),
      facing_bits: #(0xBFD09BA3, 0, 0),
      record: "Quest2.10530.links",
    ),
    StartRow(
      id: 51_596,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 29.128599166870117,
        y: -853.87158203125,
        z: -560.18798828125,
      ),
      quaternion: #(0.0, 0.9810349941253662, 0.0, -0.19383299350738525),
      facing_bits: #(0xC03017E2, 0x80000000, 0),
      record: "Quest2.10513 (a guess)",
    ),
  ]
}

/// The start row with this id.
pub fn start_row(id: Int) -> StartRow {
  let assert Ok(row) = list.find(start_rows(), fn(row) { row.id == id })
    as "the test names a row the planted tables hold"
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

/// The planted WorldLocation2 rows of the start places.
fn planted_start_rows() -> List(List(Cell)) {
  list.map(start_rows(), planted_start_row)
}

/// The planted WorldLocation2 row of a start place.
fn planted_start_row(row: StartRow) -> List(Cell) {
  location(
    id: row.id,
    world: start_place.world_id(row.place),
    zone: start_place.world_zone_id(row.place),
    position: #(
      start_place.x(row.place),
      start_place.y(row.place),
      start_place.z(row.place),
    ),
    quaternion: row.quaternion,
  )
}

/// The GameFormula row of the highest level: row 145, whose dataint0 is 50.
pub const highest_level_formula = 145

/// The XpPerLevel minXpForLevel of records 1 to 51 (the client's records 0 to
/// 50: the levels 1 to 50 and the record at the highest level).
pub fn min_xp_for_level() -> List(Int) {
  [
    0, 655, 1710, 2860, 4320, 6280, 8920, 12_510, 17_330, 23_860, 32_470, 43_830,
    58_570, 77_520, 101_530, 131_820, 169_380, 215_750, 272_350, 340_950,
    423_300, 521_770, 638_250, 775_580, 936_310, 1_123_510, 1_340_160, 1_590_200,
    1_876_730, 2_204_290, 2_576_890, 2_999_270, 3_475_990, 4_012_950, 4_614_770,
    5_288_090, 6_038_720, 6_873_450, 7_798_740, 8_822_880, 9_952_300, 11_196_140,
    12_562_350, 14_060_140, 15_698_220, 17_487_670, 19_437_010, 21_558_320,
    23_862_010, 26_360_090, 2_147_483_647,
  ]
}

/// GameFormula rows of these ids, each with `highest` as its dataint0.
pub fn game_formula_rows(
  ids ids: List(Int),
  highest highest: Int,
) -> List(List(Cell)) {
  list.map(ids, fn(id) {
    planted_table.row(game_formula.schema, [
      #("ID", Integer(id)),
      #("dataint0", Integer(highest)),
    ])
  })
}

/// XpPerLevel rows holding these minXpForLevel values as records 1 up.
pub fn xp_per_level_rows(minimums: List(Int)) -> List(List(Cell)) {
  list.index_map(minimums, fn(minimum, position) {
    planted_table.row(xp_per_level.schema, [
      #("ID", Integer(position + 1)),
      #("minXpForLevel", Integer(minimum)),
    ])
  })
}
