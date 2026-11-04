//// The cell index of a world's spawns: which spawns lie near a point, found by
//// the cells around it, so a player's move reads the few hundred spawns near
//// it and not all of the world's (up to 12,788 in one world).
////
//// - **A cell** is a square of 256 units on x and z (height is not part of the
////   cell). A spawn is in the one cell its x and z fall in. It is a server's
////   choice: the scan covers the sight circle (genesis_prime/world_map/sight)
////   whatever the size, and the size barely changes how many spawns it reads.
//// - **`near`** lists the spawns of every cell whose nearest point to a place is
////   within a range, the candidates of an exact sight check; a spawn in no
////   scanned cell is farther than the range. The map keeps the exact 3D check
////   (`sight.sees`), so the cells decide nothing a player sees.
//// - **The index is built once** when the world's spawns load, and read by the
////   maps and creatures of the world through the persistent term it sits in
////   (genesis_prime/content/spawn).

import genesis_prime/world_map/spawn_id.{type SpawnId}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// The side of a cell in units, on x and z.
const cell_size = 256.0

/// The spawns of one world by cell, each cell the pair of its x and z index
/// (`floor(x / 256)`, `floor(z / 256)`).
pub opaque type Cells {
  Cells(by_cell: Dict(#(Int, Int), List(SpawnId)))
}

/// A world's spawns with no spawn.
pub fn empty() -> Cells {
  Cells(by_cell: dict.new())
}

/// The cells of these spawns, each given as its id and its x and z.
pub fn index(spawns spawns: List(#(SpawnId, Float, Float))) -> Cells {
  Cells(
    by_cell: list.fold(spawns, dict.new(), fn(by_cell, spawn) {
      let #(id, x, z) = spawn
      dict.upsert(by_cell, cell_of(x:, z:), fn(found) {
        case found {
          Some(ids) -> [id, ..ids]
          None -> [id]
        }
      })
    }),
  )
}

/// The cell a point falls in.
pub fn cell_of(x x: Float, z z: Float) -> #(Int, Int) {
  #(cell_index(x), cell_index(z))
}

fn cell_index(coordinate: Float) -> Int {
  float.truncate(float.floor(coordinate /. cell_size))
}

/// The spawns of every cell whose nearest point to (`x`, `z`) is within `range`
/// on those two axes, in no order: the candidates of a sight check.
pub fn near(
  cells cells: Cells,
  x x: Float,
  z z: Float,
  range range: Float,
) -> List(SpawnId) {
  let #(first_x, first_z) = cell_of(x: x -. range, z: z -. range)
  let #(last_x, last_z) = cell_of(x: x +. range, z: z +. range)
  int.range(from: first_x, to: last_x + 1, with: [], run: fn(found, cell_x) {
    int.range(
      from: first_z,
      to: last_z + 1,
      with: found,
      run: fn(found, cell_z) {
        case reaches(cell_x:, cell_z:, x:, z:, range:) {
          True ->
            list.append(
              dict.get(cells.by_cell, #(cell_x, cell_z)) |> result.unwrap([]),
              found,
            )
          False -> found
        }
      },
    )
  })
}

/// Whether the cell's nearest point to (`x`, `z`) is within `range`.
fn reaches(
  cell_x cell_x: Int,
  cell_z cell_z: Int,
  x x: Float,
  z z: Float,
  range range: Float,
) -> Bool {
  let dx = x -. nearest(cell: cell_x, to: x)
  let dz = z -. nearest(cell: cell_z, to: z)
  dx *. dx +. dz *. dz <=. range *. range
}

/// The coordinate in the cell's span on one axis nearest to `to`.
fn nearest(cell cell: Int, to coordinate: Float) -> Float {
  let low = int.to_float(cell) *. cell_size
  float.clamp(coordinate, min: low, max: low +. cell_size)
}
