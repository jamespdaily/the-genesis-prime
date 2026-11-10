//// The shared character tables and the content load over them.
////
//// - `shared()` is the client's committed rows (`fixture_tables`); the tests read
////   their expected values from the same rows (`start_rows`, `row_10_look`,
////   `exile_circle_centre`).
//// - `content_tables()` is the content load over `shared()`: the client's rows of
////   World, Tutorial and Creature2OutfitInfo, with
////   `content_over` for the same load over a test's edited tables.
//// - `map_file_naming` is a CustomizationParameterMap file of one map.

import database_support
import fixture_tables
import genesis_prime/game/start_place.{type Facing, type Place, Facing}
import genesis_prime/message/float32
import genesis_prime/store.{type LookEntry, LookEntry} as _
import genesis_prime/table/character_customization
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/customization_parameter_map
import genesis_prime/table/id.{
  CharacterCustomizationId, CharacterCustomizationLabelId, WorldLocation2Id,
}
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/tutorial
import genesis_prime/table/world
import genesis_prime/table/world_location2
import gleam/int
import gleam/list
import place_support
import planted_table.{type Cell, Integer}

/// The look of the client's CharacterCustomization row 10: its two labels with
/// their values, by label.
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

/// The position of the client's WorldLocation2 row 51739, the Exile objective
/// circle's centre.
pub fn exile_circle_centre() -> #(Float, Float, Float) {
  let assert Ok(row) =
    world_location2.get(tables: shared(), id: WorldLocation2Id(51_739))
    as "the client's WorldLocation2 holds the Exile objective circle's row"
  #(row.position0, row.position1, row.position2)
}

/// The client's committed rows loaded as the server's tables.
pub fn shared() -> store.Tables {
  fixture_tables.shared()
}

/// A CustomizationParameterMap file with one map, of race 1 and sex 0, that
/// names this CustomizationParameter id.
pub fn map_file_naming(parameter_id parameter_id: Int) -> #(String, BitArray) {
  planted_table.file(customization_parameter_map.schema, [
    map(id: 1, sex: 0, parameter_id:),
  ])
}

/// The content load's own tables, read from the committed rows beside `tables`
/// on the caller's heap, and never stored.
pub fn content_over(tables tables: store.Tables) -> store.Tables {
  use folder <- planted_table.in_folder(content_files())
  let assert Ok(more) =
    server_table.load_content_tables(over: tables, from: folder)
    as "the committed rows load as the content load's tables"
  more
}

/// The committed files of the content load's own tables.
pub fn content_files() -> List(#(String, BitArray)) {
  list.map(
    [
      creature2_outfit_info.schema,
      tutorial.schema,
      world.schema,
    ],
    fixture_tables.file,
  )
}

/// The ids of the client's World rows.
pub fn content_worlds() -> List(Int) {
  fixture_tables.committed_ids(world.schema)
}

/// The content load over the shared tables, stored once and never erased.
pub fn content_tables() -> store.Tables {
  database_support.once("character_content_tables", fn() {
    store.store_under(tables: content_over(tables: shared()))
  })
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

/// A start place's WorldLocation2 row: its id, the place it stands at (world,
/// zone and position, unturned), its facing quaternion x, y, z, w, the 32 bits
/// of the yaw, pitch and roll of that facing, and the record that names the row.
pub type StartRow {
  StartRow(
    id: Int,
    place: Place,
    quaternion: #(Float, Float, Float, Float),
    facing_bits: #(Int, Int, Int),
    record: String,
  )
}

// Each start place's id, the 32 bits of its facing's yaw, pitch and roll that
// the client's QuaternionToEulerAngles (0x1401b2fe0) gives, from the emulator,
// and the record that names the row. For a turn about y alone the pitch is
// -0.0 (0x80000000), except where y < 0 and w > 0 (8223), where it is +0.0.
// 51596 is the Novice start, 42074 and 41641 the Exile Veteran start, 42148 and
// 8223 the Dominion Veteran start.
const start_facings = [
  #(42_074, #(0xC021E1A7, 0x80000000, 0), "Quest2.10528.links"),
  #(41_641, #(0x4021F773, 0x80000000, 0), "Quest2.10528.links"),
  #(42_148, #(0xC0490FDA, 0x80000000, 0), "Quest2.10530.links"),
  #(8223, #(0xBFD09BA3, 0, 0), "Quest2.10530.links"),
  #(51_596, #(0xC03017E2, 0x80000000, 0), "Quest2.10513 (a guess)"),
]

/// The start places' rows.
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

/// The place of the Novice start row: its world, zone, position and facing.
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

/// Whether the place is the row's: its world, zone, position and facing, to the
/// bit.
pub fn is_the_place_of(place place: Place, row row: StartRow) -> Bool {
  start_place.turned(place, start_place.unturned) == row.place
  && facing_bits(start_place.facing(place)) == row.facing_bits
}
