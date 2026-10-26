//// The spatial index of the map-process prototype, and the cell arithmetic the
//// one-process-per-unit prototype's table uses. It finds the units near a
//// position by reading only the cells that can hold one in range. Pure.
////
//// A unit id here is a plain `Int`, a named hot path under the typed-id rule
//// of the writing-gleam skill: the index is the code every move and every
//// look-up passes through, and the topology benchmark's two prototypes must
//// not differ by the cost of an id type.

import genesis_prime/topology/position.{type Position}
import gleam/dict.{type Dict}

/// One square of the map's grid, named by how many cell widths it lies east
/// and north of the origin. Cells on the west and south of the origin have
/// negative numbers.
pub type Cell {
  Cell(x: Int, y: Int)
}

/// The units on the map, indexed by cell. It holds each unit's position as
/// well, so `near` answers with exactly the units in range and a move knows
/// which cell to leave.
pub opaque type Grid {
  Grid(
    cell_size: Float,
    cells: Dict(Cell, List(Int)),
    positions: Dict(Int, Position),
  )
}

/// An empty grid whose cells are `cell_size` metres wide. A cell as wide as
/// the visibility range means a search reads at most nine cells.
pub fn new(cell_size: Float) -> Grid {
  todo as "body in the build commit"
}

/// The cell a position lies in, for cells `cell_size` metres wide.
pub fn cell_of(position: Position, cell_size: Float) -> Cell {
  todo as "body in the build commit"
}

/// Every cell that can hold a position within `range` metres of `position`,
/// for cells `cell_size` metres wide.
pub fn cells_near(
  position: Position,
  range: Float,
  cell_size: Float,
) -> List(Cell) {
  todo as "body in the build commit"
}

/// Adds a unit at a position. A unit already in the grid is moved.
pub fn insert(grid: Grid, unit_id: Int, position: Position) -> Grid {
  todo as "body in the build commit"
}

/// Moves a unit to a position, leaving its old cell when the new position is
/// in another. A unit not in the grid is added.
pub fn move(grid: Grid, unit_id: Int, position: Position) -> Grid {
  todo as "body in the build commit"
}

/// Takes a unit out of the grid. A unit not in the grid changes nothing.
pub fn remove(grid: Grid, unit_id: Int) -> Grid {
  todo as "body in the build commit"
}

/// The ids of the units at most `range` metres from `position`, in no
/// particular order. It reads only the cells that can hold such a unit.
pub fn near(grid: Grid, position: Position, range: Float) -> List(Int) {
  todo as "body in the build commit"
}
