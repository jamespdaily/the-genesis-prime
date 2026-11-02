//// A small set of the client's tables for the tests of the game rule, character
//// select and creating a character, which run where the client's files are
//// absent. Each row is a row of the client's own tables with the id and the
//// columns the server reads (`character_tables_test` compares each with the
//// real row where the client is present); every other column is 0.
////
//// - CharacterCreation rows 21, 338, 339, 466, 530, 536 and 539, with their xp.
//// - GameFormula row 145 (its dataint0, the highest level) and XpPerLevel
////   records 1 to 51 with their minXpForLevel, which GetLevelForExperience
////   0x140029820 reads.
//// - CharacterCustomization rows 2, 9 and 10 (race 1, sex 0) and 603 and 604
////   (race 1, sex 1) and the labels they use, 2, 21 and 22, with labels 26 and
////   27 (CharacterCustomizationLabel), which no row holds.
//// - WorldLocation2 rows 51596, 1594, 37015, 18987 and 8223,
////   the start places (genesis_prime/game/start_place), with the world, zone
////   and position of the client's row.
//// - Bone counts: opcode.0x25b.counts gives 46 bone values for race 1, sex 1
////   and 48 for race 1, sex 0. The planted maps are that many rows of one
////   parameter that sets one part, which carry those counts; the real
////   parameters are read by the real-table tests.

import character_support
import database_support
import genesis_prime/game/start_place.{type Place, Place}
import genesis_prime/table/character_creation
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/game_formula
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/world_location2
import genesis_prime/table/xp_per_level
import gleam/erlang/reference
import gleam/int
import gleam/list
import planted_table.{type Cell, Boolean, Float, Integer}

/// The planted tables, loaded once per test run under a key of their own and
/// never unloaded, as `client_tables.shared` does for the real ones.
pub fn shared() -> store.Tables {
  database_support.once("character_tables", load)
}

/// The planted files of the server's tables, each by its file name: one file
/// for every entry of `server_table.entries`, so a load of the server's list
/// from a folder of them reads every file and meets every requirement.
pub fn files() -> List(#(String, BitArray)) {
  files_with_looks(customization: customization_rows(), labels: label_rows())
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
  [
    planted_table.file(character_creation.schema, creation_rows()),
    planted_table.file(character_customization.schema, customization),
    planted_table.file(character_customization_label.schema, labels),
    planted_table.file(customization_parameter.schema, parameter_rows()),
    planted_table.file(customization_parameter_map.schema, map_rows()),
    planted_table.file(world_location2.schema, start_location_rows()),
    planted_table.file(
      game_formula.schema,
      game_formula_rows(ids: [highest_level_formula], highest: 50),
    ),
    planted_table.file(
      xp_per_level.schema,
      xp_per_level_rows(min_xp_for_level()),
    ),
  ]
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

fn creation_rows() -> List(List(Cell)) {
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
    // 466: a PreTutorial row, class 1, race 1, sex 1, faction 167, no entitlement and no cost.
    creation(
      id: 466,
      class_id: 1,
      race_id: 1,
      sex: 1,
      faction_id: 167,
      costume_only: False,
      enabled: True,
      start: 4,
      xp: 0,
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
) -> List(Cell) {
  planted_table.row(world_location2.schema, [
    #("ID", Integer(id)),
    #("position0", Float(position.0)),
    #("position1", Float(position.1)),
    #("position2", Float(position.2)),
    #("worldId", Integer(world)),
    #("worldZoneId", Integer(zone)),
  ])
}

/// The start places by their WorldLocation2 row id, each as the client's row
/// holds its world, zone and position.
pub fn start_locations() -> List(#(Int, Place)) {
  [
    #(
      1594,
      Place(
        world_id: 426,
        world_zone_id: 648,
        x: 4110.7099609375,
        y: -658.6248779296875,
        z: -5145.47998046875,
      ),
    ),
    #(
      8223,
      Place(
        world_id: 870,
        world_zone_id: 1236,
        x: -8260.708984375,
        y: -995.0770263671875,
        z: -239.0409393310547,
      ),
    ),
    #(
      18_987,
      Place(
        world_id: 1387,
        world_zone_id: 1411,
        x: -3835.3408203125,
        y: -980.2174072265625,
        z: -6050.52392578125,
      ),
    ),
    #(
      37_015,
      Place(
        world_id: 990,
        world_zone_id: 1417,
        x: -771.822998046875,
        y: -904.28515625,
        z: -2269.56005859375,
      ),
    ),
    #(
      51_596,
      Place(
        world_id: 3460,
        world_zone_id: 6009,
        x: 29.128599166870117,
        y: -853.87158203125,
        z: -560.18798828125,
      ),
    ),
  ]
}

/// The planted WorldLocation2 rows of the start places.
fn start_location_rows() -> List(List(Cell)) {
  list.map(start_locations(), fn(location_row) {
    let #(id, place) = location_row
    location(id:, world: place.world_id, zone: place.world_zone_id, position: #(
      place.x,
      place.y,
      place.z,
    ))
  })
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
