//// What the ground costs, on the real folder and the real spawn table: the time the load
//// takes to read the files, what it holds in memory, what a lookup costs, and how far the
//// retail creatures stand from the ground.
////
//// ```
//// gleam run -m genesis_prime/terrain_walk
//// ```
////
//// The environment is the server's own: PGHOST, PGPORT, PGUSER and PGPASSWORD name the
//// Postgres, PGDATABASE a database that holds the spawn table (the extractor's own is
//// `genesis_play`), GENESIS_TABLE_DIR the client's tables and GENESIS_TERRAIN_DIR the ground
//// files. The machine should be alone: run it again after `purge` for a cold page cache.
////
//// - **The load** is `content_terrain.grounds` over every spawn row with the real
////   `folder_reader`, against the same call over a reader that builds the same squares
////   in memory (no file read), in milliseconds.
//// - **Memory** is the VM's binary memory, its total and the resident size of the process
////   (`ps`), before the read and after the grounds are put under a key, each after a
////   collection, and the literal area (where the terms are put) before and after.
//// - **A lookup** is `terrain.height_at` over the creature spawns' places on the ground read
////   back from the term, in nanoseconds a call, against an empty loop and against a loop
////   that does the lookup twice (a planted change, to show the run can see one).
//// - **The creatures** are each retail creature spawn's y against the ground at its place:
////   within 2, above, below, in a hole, and with no ground, by world.

import envoy
import genesis_prime
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/terrain as content_terrain
import genesis_prime/dev_database
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/terrain.{type Ground}
import genesis_prime/world_map/spawn.{type Row}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Microsecond) -> Int

type Microsecond {
  Microsecond
}

@external(erlang, "terrain_walk_ffi", "binary_bytes")
fn binary_bytes() -> Int

@external(erlang, "terrain_walk_ffi", "total_bytes")
fn total_bytes() -> Int

@external(erlang, "terrain_walk_ffi", "resident_bytes")
fn resident_bytes() -> Int

@external(erlang, "terrain_walk_ffi", "collect")
fn collect() -> Nil

@external(erlang, "load_walk_ffi", "literal_bytes")
fn literal_bytes() -> Int

/// The number of lookups each timing makes.
const lookups = 1_000_000

pub fn main() -> Nil {
  let #(tables, _count) = genesis_prime.load_tables()
  let assert Ok(tables) =
    server_table.load_content_tables(over: tables, from: table_folder())
    as "the content tables load"
  let assert Ok(database) = dev_database.connect() as "the database answers"
  let assert Ok(rows) = content_spawn.rows(database) as "the spawn rows read"
  io.println(int.to_string(list.length(rows)) <> " spawn rows")
  let folder = terrain_folder()
  let stand_in = stand_in_file()
  let in_memory =
    timed_ms(fn() {
      content_terrain.grounds(tables:, rows:, read: fn(_asset, squares) {
        Ok(
          list.fold(squares, terrain.empty(), fn(ground, square) {
            let assert Ok(area) = terrain.area_from_file(stand_in)
              as "the stand-in file has the size of a ground file"
            terrain.with_area(ground:, row: square.0, column: square.1, area:)
          }),
        )
      })
    })
  io.println(
    "the load's check over stand-in files held in memory: "
    <> int.to_string(in_memory.1)
    <> " ms",
  )
  collect()
  let before = memory()
  let literal_before = literal_bytes()
  let from_files =
    timed_ms(fn() {
      content_terrain.grounds(
        tables:,
        rows:,
        read: content_terrain.folder_reader(folder),
      )
    })
  let assert Ok(grounds) = from_files.0 as "every spawn square has its file"
  io.println(
    "the load's read of the real files: "
    <> int.to_string(from_files.1)
    <> " ms (the whole file read, size-checked and masked)",
  )
  let key = store.new_key()
  content_terrain.put(key:, grounds:)
  collect()
  let after = memory()
  io.println(
    "memory before -> after: binary "
    <> megabytes(before.0)
    <> " -> "
    <> megabytes(after.0)
    <> " MB, total "
    <> megabytes(before.1)
    <> " -> "
    <> megabytes(after.1)
    <> " MB, resident "
    <> megabytes(before.2)
    <> " -> "
    <> megabytes(after.2)
    <> " MB; literal area "
    <> megabytes(literal_before)
    <> " -> "
    <> megabytes(literal_bytes())
    <> " MB",
  )
  let worlds =
    list.unique(list.map(rows, fn(row) { row.world_id }))
    |> list.map(fn(world_id) {
      #(world_id, content_terrain.world(key:, world_id:))
    })
    |> dict.from_list
  let creatures = list.filter(rows, fn(row: Row) { row.entity_type == 0 })
  lookup_times(worlds:, creatures:)
  creature_report(worlds:, creatures:)
}

fn table_folder() -> String {
  let assert Ok(folder) = envoy.get("GENESIS_TABLE_DIR")
    as "GENESIS_TABLE_DIR is set"
  folder
}

fn terrain_folder() -> String {
  let assert Ok(folder) = envoy.get("GENESIS_TERRAIN_DIR")
    as "GENESIS_TERRAIN_DIR is set"
  folder
}

/// A ground file with every chunk present and flat, the size of a real one, for the
/// in-memory read.
fn stand_in_file() -> BitArray {
  let chunk = bit_array.concat(list.repeat(<<0x4000:16-little>>, 361))
  bit_array.concat([<<-1:size(256)>>, ..list.repeat(chunk, 256)])
}

fn timed_ms(run: fn() -> a) -> #(a, Int) {
  let start = monotonic_time(Microsecond)
  let result = run()
  #(result, { monotonic_time(Microsecond) - start } / 1000)
}

/// The VM's binary memory, its total and the process's resident size, each in bytes.
fn memory() -> #(Int, Int, Int) {
  #(binary_bytes(), total_bytes(), resident_bytes())
}

fn megabytes(bytes: Int) -> String {
  int.to_string(bytes / 1_000_000)
}

/// The places of the creatures with the ground of their world.
fn places(
  worlds: Dict(Int, Ground),
  creatures: List(Row),
) -> List(#(Ground, Float, Float)) {
  list.map(creatures, fn(row) {
    let assert Ok(ground) = dict.get(worlds, row.world_id)
      as "every world of a spawn has a ground"
    #(ground, row.x, row.z)
  })
}

fn lookup_times(
  worlds worlds: Dict(Int, Ground),
  creatures creatures: List(Row),
) -> Nil {
  let found = places(worlds, creatures)
  let passes = lookups / list.length(found)
  let empty_loop = timed_pass(found, passes, fn(_ground, x, z) { x +. z })
  let one =
    timed_pass(found, passes, fn(ground, x, z) { height(ground:, x:, z:) })
  let two =
    timed_pass(found, passes, fn(ground, x, z) {
      height(ground:, x:, z:) +. height(ground:, x: x +. 1.0, z:)
    })
  let calls = passes * list.length(found)
  io.println(
    int.to_string(calls)
    <> " lookups: an empty loop "
    <> nanoseconds(empty_loop, calls)
    <> " ns a call, one lookup "
    <> nanoseconds(one, calls)
    <> " ns, two lookups (a planted change) "
    <> nanoseconds(two, calls)
    <> " ns",
  )
}

fn height(ground ground: Ground, x x: Float, z z: Float) -> Float {
  result.unwrap(terrain.height_at(ground:, x:, z:), 0.0)
}

fn timed_pass(
  found: List(#(Ground, Float, Float)),
  passes: Int,
  each: fn(Ground, Float, Float) -> Float,
) -> Int {
  let start = monotonic_time(Microsecond)
  let _sum =
    int.range(from: 0, to: passes, with: 0.0, run: fn(sum, _pass) {
      list.fold(found, sum, fn(sum, place) {
        sum +. each(place.0, place.1, place.2)
      })
    })
  monotonic_time(Microsecond) - start
}

fn nanoseconds(microseconds: Int, calls: Int) -> String {
  float.to_string(float.to_precision(
    int.to_float(microseconds * 1000) /. int.to_float(calls),
    1,
  ))
}

/// How each world's retail creatures stand against the ground at their place.
fn creature_report(
  worlds worlds: Dict(Int, Ground),
  creatures creatures: List(Row),
) -> Nil {
  let by_world =
    list.group(creatures, fn(row) { row.world_id })
    |> dict.to_list
    |> list.sort(fn(one, other) { int.compare(one.0, other.0) })
  io.println(
    "creatures by world: spawns, within 2, above, below, hole, no ground",
  )
  let totals =
    list.fold(by_world, [0, 0, 0, 0, 0, 0], fn(totals, held) {
      let counts = standing(worlds:, creatures: held.1)
      io.println(
        int.to_string(held.0)
        <> ": "
        <> string.join(list.map(counts, int.to_string), ", "),
      )
      list.map2(totals, counts, int.add)
    })
  io.println("all: " <> string.join(list.map(totals, int.to_string), ", "))
}

/// The count of the creatures, and how many stand within 2 of the ground, above it
/// (more than 2), below it, in a hole, and where the ground has no answer.
fn standing(
  worlds worlds: Dict(Int, Ground),
  creatures creatures: List(Row),
) -> List(Int) {
  let answers =
    list.map(creatures, fn(row) {
      let assert Ok(ground) = dict.get(worlds, row.world_id)
        as "every world of a spawn has a ground"
      #(row, terrain.height_at(ground:, x: row.x, z: row.z))
    })
  let count = fn(wanted: fn(Row, Result(Float, terrain.NoGround)) -> Bool) {
    list.count(answers, fn(answer) { wanted(answer.0, answer.1) })
  }
  [
    list.length(creatures),
    count(fn(row, answer) {
      result.map(answer, fn(ground) {
        float.absolute_value(row.y -. ground) <=. 2.0
      })
      == Ok(True)
    }),
    count(fn(row, answer) {
      result.map(answer, fn(ground) { row.y -. ground >. 2.0 }) == Ok(True)
    }),
    count(fn(row, answer) {
      result.map(answer, fn(ground) { ground -. row.y >. 2.0 }) == Ok(True)
    }),
    count(fn(_row, answer) { answer == Error(terrain.Hole) }),
    count(fn(_row, answer) {
      answer == Error(terrain.NoLayer)
      || answer == Error(terrain.NoChunk)
      || answer == Error(terrain.NoFile)
    }),
  ]
}
