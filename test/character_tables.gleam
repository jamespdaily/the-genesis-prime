//// A small set of the client's tables for the tests of the game rule, character
//// select and creating a character, which run where the client's files are
//// absent. Each row is a row of the client's own tables with the id and the
//// columns the server reads (`character_tables_test` compares each with the
//// real row where the client is present); every other column is 0.
////
//// - CharacterCreation rows 21, 338, 339, 466, 530, 536 and 539.
//// - CharacterCustomization rows 2, 9 and 10 and the labels they use, 2, 21
////   and 22 (CharacterCustomizationLabel).
//// - WorldLocation2 rows 51596, 1594, 37015, 18987, 8223, 53050 and 53051,
////   the start places (genesis_prime/game/start_place), with the world, zone
////   and position of the client's row.
//// - Bone counts: opcode.0x25b.counts gives 46 bone values for race 1, sex 1
////   and 48 for race 1, sex 0. The planted maps are that many rows of one
////   parameter that sets one part, which carry those counts; the real
////   parameters are read by the real-table tests.

import character_support
import database_support
import genesis_prime/table/character_creation
import genesis_prime/table/character_customization
import genesis_prime/table/character_customization_label
import genesis_prime/table/customization_parameter
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/world_location2
import gleam/erlang/reference
import gleam/list
import planted_table.{type Cell, Boolean, Float, Integer}

/// The planted tables, loaded once per test run under a key of their own and
/// never unloaded, as `client_tables.shared` does for the real ones.
pub fn shared() -> store.Tables {
  database_support.once("character_tables", load)
}

fn load() -> store.Tables {
  use folder <- planted_table.in_folder([
    file(character_creation.schema, creation_rows()),
    file(character_customization.schema, customization_rows()),
    file(character_customization_label.schema, label_rows()),
    file(customization_parameter.schema, parameter_rows()),
    file(customization_parameter_map.schema, map_rows()),
    file(world_location2.schema, start_location_rows()),
  ])
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: folder,
      entries: [
        character_creation.entry(),
        character_customization.entry(),
        character_customization_label.entry(),
        customization_parameter.entry(),
        customization_parameter_map.entry(),
        world_location2.entry(),
      ],
      requirements: [],
    )
    as "the planted character tables load"
  tables
}

fn file(
  schema: tbl_file.Schema,
  rows: List(List(Cell)),
) -> #(String, BitArray) {
  #(schema.file, planted_table.bytes(planted_table.table(schema, rows)))
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
      currency_type: 13,
      currency_amount: 1,
      entitlement: 0,
    ),
  ]
}

/// A CharacterCustomization row of race 1, sex 0, slot 25, flags 2.
fn customization(
  id id: Int,
  display display: Int,
  first first: #(Int, Int),
  second second: #(Int, Int),
) -> List(Cell) {
  planted_table.row(character_customization.schema, [
    #("ID", Integer(id)),
    #("raceId", Integer(1)),
    #("gender", Integer(0)),
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
    // Labels 22 = 1 and 2 = 1 (the Exile face), 22 = 2 and 2 = 1, and
    // 21 = 2 and 2 = 1 (the Dominion face).
    customization(id: 2, display: 135, first: #(22, 1), second: #(2, 1)),
    customization(id: 9, display: 136, first: #(22, 2), second: #(2, 1)),
    customization(id: 10, display: 137, first: #(21, 2), second: #(2, 1)),
  ]
}

fn label(id id: Int, faction faction: Int) -> List(Cell) {
  planted_table.row(character_customization_label.schema, [
    #("ID", Integer(id)),
    #("faction2Id", Integer(faction)),
  ])
}

fn label_rows() -> List(List(Cell)) {
  // Label 2 is for every faction, 21 for faction 166 and 22 for faction 167.
  [
    label(id: 2, faction: 0),
    label(id: 21, faction: 166),
    label(id: 22, faction: 167),
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
  let map = fn(id, sex) {
    planted_table.row(customization_parameter_map.schema, [
      #("ID", Integer(id)),
      #("raceId", Integer(1)),
      #("genderEnum", Integer(sex)),
      #("customizationParameterId", Integer(1)),
    ])
  }
  list.append(
    list.map(character_support.numbers(46), map(_, 1)),
    list.map(character_support.numbers(48), fn(index) { map(index + 46, 0) }),
  )
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

/// The start places, each as the client's row holds it.
fn start_location_rows() -> List(List(Cell)) {
  [
    location(id: 1594, world: 426, zone: 648, position: #(
      4110.7099609375,
      -658.6248779296875,
      -5145.47998046875,
    )),
    location(id: 8223, world: 870, zone: 1236, position: #(
      -8260.708984375,
      -995.0770263671875,
      -239.0409393310547,
    )),
    location(id: 18_987, world: 1387, zone: 1411, position: #(
      -3835.3408203125,
      -980.2174072265625,
      -6050.52392578125,
    )),
    location(id: 37_015, world: 990, zone: 1417, position: #(
      -771.822998046875,
      -904.28515625,
      -2269.56005859375,
    )),
    location(id: 51_596, world: 3460, zone: 6009, position: #(
      29.128599166870117,
      -853.87158203125,
      -560.18798828125,
    )),
    location(id: 53_050, world: 51, zone: 4959, position: #(
      4074.340087890625,
      -797.8367919921875,
      -2399.3701171875,
    )),
    location(id: 53_051, world: 22, zone: 4957, position: #(
      -3343.580078125,
      -887.464599609375,
      -536.030029296875,
    )),
  ]
}
