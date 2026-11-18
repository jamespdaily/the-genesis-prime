//// The ground as the server reads it at start: each served asset's `.heights` files
//// read from the terrain folder (dev/terrain_extract.py's output), checked against the
//// squares the spawn rows stand in, and put into one persistent term for each row of
//// the client's World table, under the load's key (genesis_prime/content/term).
////
//// ```
//// content.load ─▶ spawn rows ─▶ terrain.square_of ─▶ the squares each World row needs
////              ─▶ read(asset, squares) once per asset ─▶ Ground (every file of the asset)
////              ─▶ each needed square has its file, or a refusal ─▶ put(key, grounds)
//// a map's start ─▶ world(key, its world id) ─▶ Ground: no copy of the files
//// ```
////
//// - **The folder.** `<asset>/<rr><cc>.heights` for each area file the extractor wrote:
////   the area's row and column as two lower-case hex digits each (0x00 to 0x7f), 184,864
////   bytes a file. A file of another name ending `.heights`, of another size, or one the
////   folder cannot read ends the read; a file not ending `.heights` is not read.
//// - **The squares.** Every row of the `spawn` table needs the file of its square; a
////   neighbour's file is read when the folder holds it and is not needed. A World row
////   with no spawn needs none and holds an empty ground.
//// - **The term.** One `Ground` for each row of the client's World table, as the spawns'
////   terms are, so a reader of a world with no term is a bug and crashes. Worlds that
////   share an asset share its files' binaries, which live off the heap: a term holds
////   a map and a reference to each file, never its bytes.

import genesis_prime/content/refusal.{type Refusal, Refusal, RowId}
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/table/world.{type World}
import genesis_prime/terrain.{type Ground}
import genesis_prime/world_map/spawn.{type Row}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile

/// The table's name in the log and in a term.
const table = "terrain"

/// Why an asset's ground files could not be read.
pub type ReadError {
  FolderUnreadable(folder: String, reason: simplifile.FileError)
  FileUnreadable(file: String, reason: simplifile.FileError)
  /// A file ending `.heights` whose name is not an area's row and column.
  NotAnAreaName(file: String)
  /// A file that is not the 184,864 bytes of a ground file.
  NotAGroundFile(file: String)
}

/// How the load reads an asset's ground: the asset's name and the squares (area row and
/// column) the spawns need, to the asset's ground. The load's reader is `folder_reader`;
/// a test's builds a ground from synthetic files.
pub type Reader =
  fn(String, List(#(Int, Int))) -> Result(Ground, ReadError)

/// The reader of the terrain folder: every `<rr><cc>.heights` file of the asset's folder,
/// whatever squares are asked.
pub fn folder_reader(folder: String) -> Reader {
  fn(asset, _squares) { read_asset(folder <> "/" <> asset) }
}

fn read_asset(path: String) -> Result(Ground, ReadError) {
  use names <- result.try(
    simplifile.read_directory(path)
    |> result.map_error(FolderUnreadable(path, _)),
  )
  names
  |> list.filter(string.ends_with(_, ".heights"))
  |> list.sort(string.compare)
  |> list.try_fold(terrain.empty(), fn(ground, name) {
    let file = path <> "/" <> name
    use #(row, column) <- result.try(
      area_of_name(name) |> result.replace_error(NotAnAreaName(file)),
    )
    use bytes <- result.try(
      simplifile.read_bits(file) |> result.map_error(FileUnreadable(file, _)),
    )
    use area <- result.map(
      terrain.area_from_file(bytes)
      |> result.replace_error(NotAGroundFile(file)),
    )
    terrain.with_area(ground:, row:, column:, area:)
  })
}

/// The area row and column of a file named `<rr><cc>.heights`, each two lower-case hex
/// digits of 0x00 to 0x7f.
fn area_of_name(name: String) -> Result(#(Int, Int), Nil) {
  let stem = string.remove_suffix(name, ".heights")
  let lower_case_hex =
    list.all(string.to_graphemes(stem), fn(digit) {
      string.contains("0123456789abcdef", digit)
    })
  use <- bool.guard(!{ string.length(stem) == 4 && lower_case_hex }, Error(Nil))
  use row <- result.try(int.base_parse(string.slice(stem, 0, 2), 16))
  use column <- result.try(int.base_parse(string.slice(stem, 2, 2), 16))
  case row <= 0x7f && column <= 0x7f {
    True -> Ok(#(row, column))
    False -> Error(Nil)
  }
}

/// The reason a read failed, in words, naming the file or the folder.
fn describe_read(error error: ReadError) -> String {
  case error {
    FolderUnreadable(folder:, reason:) ->
      "the folder "
      <> folder
      <> " could not be read: "
      <> simplifile.describe_error(reason)
    FileUnreadable(file:, reason:) ->
      "the file "
      <> file
      <> " could not be read: "
      <> simplifile.describe_error(reason)
    NotAnAreaName(file:) ->
      "the file "
      <> file
      <> " is not named <rr><cc>.heights, the area's row and column of 00 to 7f in lower-case hex"
    NotAGroundFile(file:) ->
      "the file " <> file <> " is not the 184,864 bytes of a ground file"
  }
}

/// The name of the asset a World row's maps load, the last part of its asset path (whose
/// parts are split by a backslash), or an empty name when the row has none.
pub fn asset(world world: World) -> String {
  case list.last(string.split(world.asset_path, "\\")) {
    Ok(last) -> last
    Error(Nil) -> ""
  }
}

/// The ground of every row of the World table: the asset's files for a world a spawn
/// stands in, an empty ground for the others; or a refusal for each world whose asset
/// cannot be read and each square a spawn stands in that has no file. `read` is asked
/// once for each asset, with the squares of every world that uses it.
pub fn grounds(
  tables tables: store.Tables,
  rows rows: List(Row),
  read read: Reader,
) -> Result(Dict(Int, Ground), List(Refusal)) {
  let needed = squares_needed(rows)
  let worlds = world.all(tables)
  let by_asset =
    list.fold(worlds, dict.new(), fn(by_asset, world) {
      case dict.get(needed, world.id) {
        Ok(squares) ->
          dict.upsert(by_asset, asset(world:), fn(held) {
            set.union(option.unwrap(held, set.new()), squares)
          })
        Error(Nil) -> by_asset
      }
    })
  let reads =
    dict.map_values(by_asset, fn(asset, squares) {
      read(asset, ordered(squares))
    })
  let results =
    list.map(worlds, fn(world) {
      case dict.get(needed, world.id) {
        Error(Nil) -> #(world.id, Ok(terrain.empty()))
        Ok(squares) -> #(world.id, ground_of(world:, squares:, reads:))
      }
    })
  case list.flat_map(results, fn(held) { result.unwrap_error(held.1, []) }) {
    [] ->
      Ok(
        dict.from_list(
          list.filter_map(results, fn(held) {
            result.map(held.1, fn(ground) { #(held.0, ground) })
          }),
        ),
      )
    refusals -> Error(refusals)
  }
}

/// The squares each world's spawns stand in; a spawn outside the world is the spawn
/// selection's refusal, not the ground's.
fn squares_needed(rows: List(Row)) -> Dict(Int, Set(#(Int, Int))) {
  list.fold(rows, dict.new(), fn(needed, row) {
    case terrain.square_of(x: row.x, z: row.z) {
      Ok(square) ->
        dict.upsert(needed, row.world_id, fn(held) {
          set.insert(option.unwrap(held, set.new()), square)
        })
      Error(Nil) -> needed
    }
  })
}

fn ordered(squares: Set(#(Int, Int))) -> List(#(Int, Int)) {
  list.sort(set.to_list(squares), fn(one, other) {
    int.compare(one.0 * 128 + one.1, other.0 * 128 + other.1)
  })
}

/// A world's ground out of its asset's read, or a refusal for the read's failure and
/// one for each square its spawns need that the read lacks.
fn ground_of(
  world world: World,
  squares squares: Set(#(Int, Int)),
  reads reads: Dict(String, Result(Ground, ReadError)),
) -> Result(Ground, List(Refusal)) {
  let name = asset(world:)
  let refuse = fn(rule) { Refusal(table:, row: RowId(world.id), rule:) }
  case name, dict.get(reads, name) {
    "", _ -> Error([refuse("the World row names no asset to read ground from")])
    _, Error(Nil) -> Error([refuse("the asset " <> name <> " was not read")])
    _, Ok(Error(error)) ->
      Error([
        refuse(
          "the ground files of the asset "
          <> name
          <> " were not read: "
          <> describe_read(error:),
        ),
      ])
    _, Ok(Ok(ground)) ->
      case
        list.filter(ordered(squares), fn(square) {
          !dict.has_key(ground.areas, square.0 * 128 + square.1)
        })
      {
        [] -> Ok(ground)
        missing ->
          Error(
            list.map(missing, fn(square) {
              refuse(
                "no ground file "
                <> name
                <> "/"
                <> file_name(row: square.0, column: square.1)
                <> " for a spawn in it",
              )
            }),
          )
      }
  }
}

/// The file name of an area: its row and column as two lower-case hex digits each.
fn file_name(row row: Int, column column: Int) -> String {
  hex(row) <> hex(column) <> ".heights"
}

fn hex(number: Int) -> String {
  string.pad_start(string.lowercase(int.to_base16(number)), to: 2, with: "0")
}

/// Writes each world's ground under the key, once.
pub fn put(key key: Key, grounds grounds: Dict(Int, Ground)) -> Nil {
  dict.each(grounds, fn(world_id, ground) {
    store.put_content(key:, table:, id: world_id, value: ground)
  })
}

/// The world's ground, as the load put it under the key. The load puts a term for every
/// row of the client's World table before the tree starts, so a world with no term is a
/// bug and crashes the reader.
pub fn world(key key: Key, world_id world_id: Int) -> Ground {
  store.content(key:, table:, id: world_id)
}
