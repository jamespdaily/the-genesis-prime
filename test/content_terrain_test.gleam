//// The ground at start (`genesis_prime/content/terrain`): the folder of ground files
//// read as the extractor wrote it (`<asset>/<rr><cc>.heights`, the area's row and
//// column as two lower-case hex digits each, 184,864 bytes a file; dev/terrain_extract.py's
//// header), the load's check that every square a spawn stands in has its file, and
//// the load's refusal that puts no term when a file is missing.

import character_tables
import content_support
import database_support
import genesis_prime/content
import genesis_prime/content/refusal.{Refusal, RowId}
import genesis_prime/content/terrain as content_terrain
import genesis_prime/terrain
import genesis_prime/world_map/spawn.{type Row}
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import owned_test
import spawn_support
import terrain_support

/// A spawn of World 3460 (asset NewPlayerExperience) at the place, in the area of
/// row 0x34 and column 0x47 when it is (3600, -6100): 64 + floor(-6100 / 512) = 52
/// and 64 + floor(3600 / 512) = 71 (area_file.cell).
fn spawn_at(x x: Float, z z: Float) -> Row {
  spawn.Row(..spawn_support.beast_row(number: 1), x:, z:)
}

pub fn the_folder_reader_reads_each_heights_file_and_ignores_the_rest_test() -> Nil {
  use <- owned_test.run(60_000)
  let first = terrain_support.uniform_file(raw: 10_000)
  let second = terrain_support.uniform_file(raw: 20_000)
  use folder <- terrain_support.planted_folder([
    #("Eastern/3447.heights", first),
    #("Eastern/3448.heights", second),
    #("Eastern/notes.txt", <<"a stray file">>),
    #("state.json", <<"{}">>),
  ])
  let assert Ok(ground) = content_terrain.folder_reader(folder)("Eastern", [])
    as "a folder of ground files reads"
  assert list.sort(dict.keys(ground.areas), int.compare)
    == [52 * 128 + 71, 52 * 128 + 72]
    as "the files 3447 and 3448 are the areas (0x34, 0x47) and (0x34, 0x48), keys row * 128 + column, and nothing else is read"
  // Area (0x34, 0x47) holds x 3584 to 4096 and z -6144 to -5632 (area_file.cell).
  assert terrain_support.is_height_of(
    terrain.height_at(ground:, x: 3600.0, z: -6100.0),
    raw: 10_000,
  )
    as "the first file's chunks answer in its own area"
  assert terrain_support.is_height_of(
    terrain.height_at(ground:, x: 4100.0, z: -6100.0),
    raw: 20_000,
  )
    as "the second file's chunks answer in the next column's area"
}

/// A folder the load refuses: its files, and the words the refusal of World 3460
/// names.
type Refused {
  Refused(
    name: String,
    files: List(#(String, BitArray)),
    names: String,
    read_fails_as: String,
  )
}

fn read_error_kind(error: content_terrain.ReadError) -> String {
  case error {
    content_terrain.FolderUnreadable(..) -> "an unreadable folder"
    content_terrain.FileUnreadable(..) -> "an unreadable file"
    content_terrain.NotAnAreaName(..) -> "a name that is no area"
    content_terrain.NotAGroundFile(..) -> "a file of the wrong size"
  }
}

pub fn a_folder_the_server_cannot_use_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let flat = terrain_support.flat_file()
  let short = bit_array_without_last_byte(flat)
  let cases = [
    Refused(
      "the asset's folder is missing",
      [#("Western/4040.heights", flat)],
      "NewPlayerExperience",
      "an unreadable folder",
    ),
    Refused(
      "a ground file one byte short is never read as ground",
      [#("NewPlayerExperience/4040.heights", short)],
      "4040.heights",
      "a file of the wrong size",
    ),
    Refused(
      "a file whose column is 0x80 is outside the 128 columns and is not merged with the next row's column 0",
      [
        #("NewPlayerExperience/4040.heights", flat),
        #("NewPlayerExperience/4080.heights", flat),
        #("NewPlayerExperience/4100.heights", flat),
      ],
      "4080.heights",
      "a name that is no area",
    ),
  ]
  list.each(cases, fn(held) {
    use folder <- terrain_support.planted_folder(held.files)
    let refused =
      content_terrain.grounds(
        tables: character_tables.content_tables(),
        rows: [spawn_at(x: 0.0, z: 0.0)],
        read: content_terrain.folder_reader(folder),
      )
    let assert Error([Refusal(table:, row:, rule:)]) = refused as held.name
    assert table == "terrain" && row == RowId(3460) as held.name
    assert string.contains(rule, held.names) as held.name
    let assert Error(error) =
      content_terrain.folder_reader(folder)("NewPlayerExperience", [])
      as held.name
    assert read_error_kind(error) == held.read_fails_as as held.name
  })
}

fn bit_array_without_last_byte(bytes: BitArray) -> BitArray {
  let assert Ok(short) =
    bit_array.slice(bytes, 0, bit_array.byte_size(bytes) - 1)
    as "a file has bytes"
  short
}

pub fn a_spawn_square_needs_its_file_and_a_neighbour_does_not_test() -> Nil {
  use <- owned_test.run(60_000)
  let row = spawn_at(x: 3600.0, z: -6100.0)
  let flat = terrain_support.flat_file()
  let read = fn(files) {
    use folder <- terrain_support.planted_folder(files)
    content_terrain.grounds(
      tables: character_tables.content_tables(),
      rows: [row],
      read: content_terrain.folder_reader(folder),
    )
  }
  let assert Ok(grounds) = read([#("NewPlayerExperience/3447.heights", flat)])
    as "the spawn's own file is enough: a neighbour's is not required"
  let assert Ok(ground) = dict.get(grounds, 3460) as "World 3460 has a ground"
  assert terrain_support.is_height_of(
    terrain.height_at(ground:, x: 3600.0, z: -6100.0),
    raw: terrain_support.flat_raw,
  )
    as "the spawn's own square has ground"
  assert terrain.height_at(ground:, x: 4100.0, z: -6100.0)
    == Error(terrain.NoFile)
    as "the neighbour's square has no file and answers no ground"
  let assert Error([Refusal(table: "terrain", row: RowId(3460), rule:)]) =
    read([#("NewPlayerExperience/3448.heights", flat)])
    as "a spawn whose own file is missing is refused whatever its neighbour holds"
  assert string.contains(rule, "3447.heights")
    as "the refusal names the file of the spawn's square"
}

pub fn a_load_with_a_spawn_square_missing_puts_no_terrain_term_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert [square, ..] =
    content_support.stored_spawns(database:)
    |> list.filter(fn(row) { row.world_id == 3460 })
    |> list.filter_map(fn(row) { terrain.square_of(x: row.x, z: row.z) })
    as "a migrated database seeds spawns in World 3460"
  let #(loaded, key) =
    content_support.load_terrain(
      database:,
      terrain: terrain_support.flat_reader_without(dropped: [square]),
    )
  let assert Error(content.Refused(refusals:)) = loaded
    as "a spawn square with no file stops the start"
  assert list.any(refusals, fn(refused) {
    refused.table == "terrain"
    && string.contains(
      refusal.describe(refused),
      terrain_support.file_name(row: square.0, column: square.1),
    )
  })
    as "the refusals include the terrain one, naming the missing file"
  assert content_support.terms(key) == []
    as "a refused load puts no term under the key (the terms are put only when no row is refused)"
}
