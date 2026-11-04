//// The cell index of a world's spawns (`genesis_prime/world_map/spawn_cell`).
//// Expected values come from the rule the module states: a cell is a square of
//// 256 units on x and z, a spawn is in the one cell its x and z fall in, and
//// `near` lists the spawns of every cell whose nearest point to a place is within
//// the range, so a spawn within the range of a place is always among them.

import genesis_prime/world_map/spawn_cell
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import gleam/int
import gleam/list
import owned_test

/// Spawns 1 to 6 at known points: the first two share a cell.
fn spawns() -> List(#(SpawnId, Float, Float)) {
  [
    #(SpawnId(1), 10.0, 10.0),
    #(SpawnId(2), 255.9, 255.9),
    #(SpawnId(3), 256.0, 0.0),
    #(SpawnId(4), -0.1, -0.1),
    #(SpawnId(5), 1200.0, 0.0),
    #(SpawnId(6), 0.0, 3000.0),
  ]
}

fn sorted(ids: List(SpawnId)) -> List(Int) {
  list.map(ids, fn(id) {
    let SpawnId(number) = id
    number
  })
  |> list.sort(int.compare)
}

pub fn a_point_falls_in_the_cell_of_its_x_and_z_floored_by_256_test() -> Nil {
  use <- owned_test.run(5000)
  assert spawn_cell.cell_of(x: 0.0, z: 0.0) == #(0, 0)
  assert spawn_cell.cell_of(x: 255.9, z: 255.9) == #(0, 0)
    as "255.9 is the last of the first cell"
  assert spawn_cell.cell_of(x: 256.0, z: 512.0) == #(1, 2)
    as "256 starts the second cell on x, 512 the third on z"
  assert spawn_cell.cell_of(x: -0.1, z: -256.0) == #(-1, -1)
    as "a negative coordinate floors toward minus infinity: -0.1 is in cell -1, -256 starts it"
}

pub fn every_spawn_sits_in_its_own_cell_and_is_found_from_its_own_point_test() -> Nil {
  use <- owned_test.run(5000)
  let cells = spawn_cell.index(spawns())
  list.each(spawns(), fn(spawn) {
    let #(id, x, z) = spawn
    assert list.contains(spawn_cell.near(cells:, x:, z:, range: 0.0), id)
      as "a place on the spawn finds it, whatever the range"
  })
  assert sorted(spawn_cell.near(cells:, x: 0.0, z: 0.0, range: 0.0)) == [1, 2]
    as "range 0 reads only the cell of the place: spawns 1 and 2 share cell (0, 0), and 4 is in cell (-1, -1)"
}

pub fn near_finds_every_spawn_within_the_range_and_none_beyond_the_scanned_cells_test() -> Nil {
  use <- owned_test.run(5000)
  let cells = spawn_cell.index(spawns())
  let found = spawn_cell.near(cells:, x: 0.0, z: 0.0, range: 1024.0)
  assert sorted(found) == [1, 2, 3, 4, 5]
    as "spawns 1 to 4 lie within 1024 units of the origin; 5 at 1200 is a candidate, since its cell (1024 to 1280) starts exactly 1024 away, and the exact sight check decides it; 6 at 3000 is far"
  assert list.contains(
    spawn_cell.near(cells:, x: 300.0, z: 0.0, range: 1024.0),
    SpawnId(5),
  )
    as "from x 300 the spawn at 1200 is 900 away, so its cell is scanned"
}
