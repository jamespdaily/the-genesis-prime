//// The server's ground read from the real ground files (dev/terrain_extract.py's
//// folder) against the retail spawns of the world database, which hold the
//// positions the client lacks. It runs where the client, the world data and the folder
//// are present (tag `world_data`), and passes beside the other world-data tests.

import client_tables
import content_support
import database_support
import envoy
import genesis_prime/content/terrain as content_terrain
import genesis_prime/game/click_objective
import genesis_prime/game/kill_objective
import genesis_prime/game/start_place
import genesis_prime/import_world_data
import genesis_prime/shared/quest_row
import genesis_prime/table/id
import genesis_prime/table/quest_objective
import genesis_prime/table/world_location2
import genesis_prime/terrain.{type Ground}
import genesis_prime/world_map/objective_spawn
import genesis_prime/world_map/spawn.{type Row}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import owned_test
import spawn_support
import terrain_support
import unitest

/// Every spawn row of the world database, through the real folder, against what the
/// client's own data says:
/// - every stored row has the file of its square (a spawn's square with no file
///   would stop the start);
/// - the 481 retail creatures of World 426's landing area (x 3600 to 4700, z -6000
///   to -5000): 11 stand in a hole cell, and the other 470 stand at the ground's
///   height to within 0.001 at the median and 1.2 at the 90th percentile
///   (area_file.ground_height's measure: 0.00027 and 1.101, the rest on props);
/// - the creatures standing in a chunk with no layer 0 (the client's shared default,
///   0x1402e5c40) are 17, all in World 3460, whose y is about -447 on objects;
/// - a chunk border reads the same from both chunks (0x14037d790: the border
///   vertices are shared), for 100 borders in each of the Western and Eastern files.
pub fn the_real_ground_answers_the_retail_spawns_of_every_served_world_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  use <- unitest.guard(terrain_support.real_folder_present())
  let assert Ok(world_data) = envoy.get("GENESIS_WORLD_DATA")
    as "the guard saw the variable"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder: world_data,
    )
    as "the world database imports"
  let stored = content_support.stored_spawns(database:)
  let assert Ok(grounds) =
    content_terrain.grounds(
      tables: client_tables.with_content_tables(),
      rows: stored,
      read: content_terrain.folder_reader(terrain_support.real_folder()),
    )
    as "every spawn row of the world database has its ground file"
  let creatures = list.filter(stored, fn(row: Row) { row.entity_type == 0 })
  let ground_of = fn(world_id) {
    let assert Ok(ground) = dict.get(grounds, world_id)
      as "every World row has a ground"
    ground
  }
  landing_area_of_world_426(ground_of(426), creatures)
  assert no_layer_by_world(ground_of:, creatures:) == [#(3460, 17)]
    as "the creatures in a chunk with no layer 0 are 17, all in World 3460 (the worlds with none are left out)"
  list.each([22, 51], fn(world_id) {
    chunk_borders_agree(ground_of(world_id), samples: 100)
  })
}

/// What the placement made over the real tables, world database and ground files: every
/// placed row, kill and click, the markers of the objectives, and the ground of each world.
type RealPlacement {
  RealPlacement(
    rows: List(Row),
    markers: List(world_location2.WorldLocation2),
    grounds: Dict(Int, Ground),
  )
}

fn placed_over_the_real_ground() -> RealPlacement {
  let assert Ok(world_data) = envoy.get("GENESIS_WORLD_DATA")
    as "the guard saw the variable"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_world_data.import_spawns(
      db: content_support.connect(database:),
      folder: world_data,
    )
    as "the world database imports"
  let stored = content_support.stored_spawns(database:)
  let tables = client_tables.with_content_tables()
  let assert Ok(grounds) =
    content_terrain.grounds(
      tables:,
      rows: stored,
      read: content_terrain.folder_reader(terrain_support.real_folder()),
    )
    as "every spawn row of the world database has its ground file"
  let placed =
    objective_spawn.place(
      tables:,
      stored:,
      factions: spawn_support.the_boss_is_given_233(tables:),
      kinds: spawn_support.turret_kinds(),
      kills: content_support.objective_ids(table: kill_objective.table),
      clicks: content_support.objective_ids(table: click_objective.table),
      grounds:,
    )
  let markers =
    quest_objective.all(tables)
    |> list.flat_map(fn(objective) { quest_row.marker_ids(objective:) })
    |> list.unique
    |> list.filter_map(fn(marker_id) {
      world_location2.get(tables:, id: id.WorldLocation2Id(marker_id))
    })
  RealPlacement(
    rows: list.append(placed.rows, placed.click_rows),
    markers:,
    grounds:,
  )
}

/// The creatures a kill or click objective's marker places on the marker's ring, over
/// the real ground files. For each marker whose centre stands on the ground (its
/// height within 2 of the ground read at the centre, the band the client lifts a unit
/// by), every placed row on the marker's half-radius ring whose place has a ground read
/// stands within 0.001 of that read when the read is within the ring's radius plus 2
/// of the marker's height (a slope no steeper than 45 degrees from the centre, and the
/// client's lift), and within 0.001 of the marker's own height when it is not; so no
/// ring row stands farther from the marker's height than that band.
/// World 22's markers 29628 and 45150 (ring radii 79.9 and 115, height -798.837) have
/// rings that reach raw 0x1FFF cells, a floor 225 below the marker.
pub fn a_ring_creature_of_a_surface_marker_stands_on_the_real_ground_within_the_ring_band_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  use <- unitest.guard(terrain_support.real_folder_present())
  let RealPlacement(rows:, markers:, grounds:) = placed_over_the_real_ground()
  let on_surface_rings =
    list.flat_map(markers, fn(marker) {
      ring_rows_of(marker:, rows:, grounds:, standing: OnTheGround)
    })
    |> list.filter_map(fn(ring_row) {
      let #(row, marker) = ring_row
      let assert Ok(ground) = dict.get(grounds, marker.world_id)
        as "a marker with ring rows is in a world with a ground"
      terrain.height_at(ground:, x: row.x, z: row.z)
      |> result.map(fn(height) { #(row, marker, height) })
      |> result.replace_error(Nil)
    })
  assert on_surface_rings != []
    as "some placed rows stand on the ring of a surface marker, at a place with a ground read"
  let stands_wrongly =
    list.filter(on_surface_rings, fn(ring_row) {
      let #(row, marker, ground) = ring_row
      let expected = case
        float.absolute_value(ground -. marker.position1)
        <=. marker.radius /. 2.0 +. 2.0
      {
        True -> ground
        False -> marker.position1
      }
      float.absolute_value(row.y -. expected) >=. 0.001
    })
    |> list.map(fn(ring_row) {
      let #(row, marker, ground) = ring_row
      #(marker.id, row.creature_id, row.y, marker.position1, ground)
    })
  assert stands_wrongly == []
    as "a ring row of a surface marker stands on the ground read at its place when that read is within the ring's radius plus 2 of the marker's height, and at the marker's height when it is not"
  let at_pinned_markers =
    list.filter(on_surface_rings, fn(ring_row) {
      list.contains([29_628, 45_150], { ring_row.1 }.id)
    })
  assert at_pinned_markers != []
    as "World 22's markers 29628 and 45150 hold ring rows at a place with a ground read"
  assert list.all(at_pinned_markers, fn(ring_row) {
    let #(row, marker, _ground) = ring_row
    float.absolute_value(row.y -. marker.position1)
    <=. marker.radius /. 2.0 +. 2.0
  })
    as "those rows stand within the ring's radius plus 2 of the marker's height, -798.837, not on the floor of raw 0x1FFF, -1024.094"
}

/// A marker below or above the ground at its centre (an interior, a cave, a prop) is not
/// asked to stand on the ground: every placed row on its ring, over the real ground
/// files, keeps the marker's height whatever ground lies under or over the slot.
pub fn a_ring_creature_of_a_marker_off_the_ground_keeps_the_markers_height_over_the_real_ground_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.tag("world_data")
  use <- unitest.guard(client_tables.present())
  use <- unitest.guard(envoy.get("GENESIS_WORLD_DATA") != Error(Nil))
  use <- unitest.guard(terrain_support.real_folder_present())
  let RealPlacement(rows:, markers:, grounds:) = placed_over_the_real_ground()
  let off_the_ground_rings =
    list.flat_map(markers, fn(marker) {
      ring_rows_of(marker:, rows:, grounds:, standing: OffTheGround)
    })
  assert off_the_ground_rings != []
    as "some placed rows stand on the ring of a marker above or below its centre's ground"
  assert list.filter(off_the_ground_rings, fn(ring_row) {
      let #(row, marker) = ring_row
      float.absolute_value(row.y -. marker.position1) >=. 0.001
    })
    |> list.map(fn(ring_row) {
      let #(row, marker) = ring_row
      #(marker.id, row.creature_id, row.y, marker.position1)
    })
    == []
    as "a ring row of a marker above or below its centre's ground keeps the marker's height"
}

/// Whether a marker's centre stands on the ground: its height is within 2 of the ground
/// read there (the band the client lifts a unit by).
type Standing {
  OnTheGround
  OffTheGround
}

/// The rows on the half-radius ring of the marker, each with the marker, when its centre
/// has a ground read and stands as `standing` says; none for a marker whose centre has
/// no ground read.
fn ring_rows_of(
  marker marker: world_location2.WorldLocation2,
  rows rows: List(Row),
  grounds grounds: Dict(Int, Ground),
  standing standing: Standing,
) -> List(#(Row, world_location2.WorldLocation2)) {
  let assert Ok(centre) = start_place.of_row(row: marker)
    as "a marker with a placed row has a start place"
  let centre_x = start_place.x(centre)
  let centre_z = start_place.z(centre)
  let found_standing = {
    use ground <- result.try(
      dict.get(grounds, marker.world_id) |> result.replace_error(Nil),
    )
    use under_centre <- result.try(
      terrain.height_at(ground:, x: centre_x, z: centre_z)
      |> result.replace_error(Nil),
    )
    case float.absolute_value(start_place.y(centre) -. under_centre) <=. 2.0 {
      True -> Ok(OnTheGround)
      False -> Ok(OffTheGround)
    }
  }
  case found_standing {
    Ok(found) if found == standing ->
      list.filter_map(rows, fn(row: Row) {
        let across =
          distance(across: row.x -. centre_x, down: row.z -. centre_z)
        case
          row.world_id == marker.world_id
          && float.absolute_value(across -. marker.radius /. 2.0) <. 0.001
        {
          True -> Ok(#(row, marker))
          False -> Error(Nil)
        }
      })
    Ok(_) | Error(Nil) -> []
  }
}

fn distance(across across: Float, down down: Float) -> Float {
  let assert Ok(root) = float.square_root(across *. across +. down *. down)
    as "a sum of squares has a root"
  root
}

fn landing_area_of_world_426(ground: Ground, creatures: List(Row)) -> Nil {
  let landing =
    list.filter(creatures, fn(row: Row) {
      row.world_id == 426
      && row.x >=. 3600.0
      && row.x <=. 4700.0
      && row.z >=. -6000.0
      && row.z <=. -5000.0
    })
  assert list.length(landing) == 481
    as "World 426's retail creatures in the landing area"
  let answers =
    list.map(landing, fn(row) {
      #(row, terrain.height_at(ground:, x: row.x, z: row.z))
    })
  assert list.count(answers, fn(answer) { answer.1 == Error(terrain.Hole) })
    == 11
    as "11 creatures stand in hole cells"
  let misses =
    list.filter_map(answers, fn(answer) {
      answer.1
      |> result.map(fn(found) { float.absolute_value(answer.0.y -. found) })
      |> result.replace_error(Nil)
    })
    |> list.sort(float.compare)
  assert list.length(misses) == 470 as "the other creatures have ground"
  assert nth(misses, 235) <. 0.001
    as "the median miss is under 0.001 (measured 0.00027)"
  assert nth(misses, 423) <. 1.2
    as "the 90th percentile miss is under 1.2 (measured 1.101: creatures on props)"
}

fn nth(sorted: List(Float), at: Int) -> Float {
  let assert [found, ..] = list.drop(sorted, at) as "the list is long enough"
  found
}

/// For each world that has any, how many creatures stand where the ground has no
/// layer, in world order.
fn no_layer_by_world(
  ground_of ground_of: fn(Int) -> Ground,
  creatures creatures: List(Row),
) -> List(#(Int, Int)) {
  creatures
  |> list.map(fn(row) { row.world_id })
  |> list.unique
  |> list.sort(int.compare)
  |> list.filter_map(fn(world_id) {
    let ground = ground_of(world_id)
    let count =
      list.count(creatures, fn(row: Row) {
        row.world_id == world_id
        && terrain.height_at(ground:, x: row.x, z: row.z)
        == Error(terrain.NoLayer)
      })
    case count {
      0 -> Error(Nil)
      _ -> Ok(#(world_id, count))
    }
  })
}

/// Samples borders between two chunks of one area, spread over the ground's areas,
/// and checks the height on the border against the height 1e-9 below it. A sample in
/// a hole or a chunk the file lacks is passed over; most are not.
fn chunk_borders_agree(ground: Ground, samples samples: Int) -> Nil {
  let areas = list.sort(dict.keys(ground.areas), int.compare)
  let compared =
    list.index_map(areas, fn(key, at) { #(key, at) })
    |> list.take(samples)
    |> list.count(fn(held) {
      let #(key, at) = held
      let across =
        int.to_float({ key % 128 - 64 } * 512 + { at * 7 % 15 + 1 } * 32)
      let down = int.to_float({ key / 128 - 64 } * 512 + 1 + at * 37 % 500)
      let on = terrain.height_at(ground:, x: across, z: down)
      let under = terrain.height_at(ground:, x: across -. 1.0e-9, z: down)
      let agreement =
        result.try(on, fn(on) {
          result.map(under, float.loosely_equals(
            on,
            with: _,
            tolerating: 1.0e-6,
          ))
        })
      assert agreement != Ok(False)
        as "the two chunks agree on their shared border"
      agreement == Ok(True)
    })
  assert compared >= samples / 2
    as "most sampled borders have ground on both sides"
}
