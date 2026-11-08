//// The shared character tables, the content load over them, and the planted
//// tables of the character tests, which run where the client's files are absent.
////
//// - `shared()` is the client's committed rows (`fixture_tables`): a character's
////   look, start place, zones, chat channels, levels and Novice loadout all come
////   from them, and the tests read their expected values from the same rows
////   (`start_rows`, `row_10_look`, `exile_circle_centre`).
//// - `content_tables()` is the content load over `shared()`: the client's rows of
////   Creature2's tables, Faction2, Faction2Relationship, World and the spell
////   trees, with `content_over` for the same load over a test's edited tables.
//// - `files()` is the planted folder the server's tables read: the client's rows
////   of the creature tables, WorldLocation2, WorldZone, ChatChannel, GameFormula,
////   XpPerLevel and Prerequisite (`fixture_tables.file`), the CharacterCreation,
////   customization, label, parameter and map rows planted here, and the Novice
////   gear of `novice_tables`.
////   It holds no spell rows of the Novice loadout: a test that casts reads
////   `shared()`.
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
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
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
import planted_table.{type Cell, Boolean, Integer}
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

/// The committed files of the creature tables.
fn creature_files() -> List(#(String, BitArray)) {
  list.map(
    [
      creature2.schema,
      creature2_arche_type.schema,
      creature2_difficulty.schema,
      creature2_tier.schema,
      creature2_resist.schema,
      creature2_display_info.schema,
      creature2_display_group_entry.schema,
      creature2_override_properties.schema,
      creature2_outfit_group_entry.schema,
      instance_portal.schema,
      path_mission.schema,
    ],
    fixture_tables.file,
  )
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
    fixture_tables.file(prerequisite.schema),
    fixture_tables.file(positional_requirement.schema),
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

/// The tables only the content load reads, read beside `tables` from the
/// committed rows of the client's content tables (`server_table.content_entries`),
/// on the caller's heap: the content load over a load the caller edited.
pub fn content_over(tables tables: store.Tables) -> store.Tables {
  use folder <- planted_table.in_folder(content_files())
  let assert Ok(more) =
    server_table.load_content_tables(over: tables, from: folder)
    as "the committed rows load as the content load's tables"
  more
}

/// The committed files of the tables only the content load reads
/// (`server_table.content_entries`).
pub fn content_files() -> List(#(String, BitArray)) {
  list.map(
    [
      creature2_outfit_info.schema,
      faction2.schema,
      faction2_relationship.schema,
      world.schema,
    ],
    fixture_tables.file,
  )
}

/// The ids of the Worlds the client's rows hold, the worlds a test's map may run
/// in.
pub fn content_worlds() -> List(Int) {
  fixture_tables.committed_ids(world.schema)
}

/// The content load over the shared tables: the tables only the content load
/// reads, loaded once from the committed rows beside the stored tables. Stored
/// once and never erased, as `shared` is.
pub fn content_tables() -> store.Tables {
  database_support.once("character_content_tables", fn() {
    store.store_under(tables: content_over(tables: shared()))
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
