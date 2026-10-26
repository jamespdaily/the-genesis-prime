//// The spatial index of a map: the units on it by cell, so the units near a
//// position are found by reading only the cells that can hold one in range.
//// Pure.
////
//// A unit id here is a plain `Int`, a named hot path under the typed-id rule of
//// the writing-gleam skill: the index is the code every look-up passes
//// through, as it was in the topology trial (`id_cost` measured a typed id at
//// about 5% of a hot path's time).

import genesis_prime/map/position.{type Position}

/// One cube of the map's grid, named by how many cell widths it lies along each
/// axis from the origin. Cells on the negative side of an axis have negative
/// numbers.
pub type Cell {
  Cell(x: Int, y: Int, z: Int)
}

/// The units on the map, indexed by cell. It holds each unit's position as
/// well, so `near` answers with exactly the units in range and a move knows
/// which cell to leave.
pub opaque type Grid {
  Grid
}

/// An empty grid whose cells are `cell_size` metres wide. A cell as wide as the
/// range searched means a search reads at most 27 cells.
pub fn new(cell_size cell_size: Float) -> Grid {
  todo as "an empty grid"
}

/// The cell a position lies in, for cells `cell_size` metres wide.
pub fn cell_of(
  position position: Position,
  cell_size cell_size: Float,
) -> Cell {
  todo as "the cell of a position"
}

/// Every cell that can hold a position within `range` metres of `position`,
/// for cells `cell_size` metres wide.
pub fn cells_near(
  position position: Position,
  range range: Float,
  cell_size cell_size: Float,
) -> List(Cell) {
  todo as "the cells near a position"
}

/// Adds a unit at a position. A unit already in the grid is moved.
pub fn insert(
  grid grid: Grid,
  unit_id unit_id: Int,
  position position: Position,
) -> Grid {
  todo as "adds a unit"
}

/// Takes a unit out of the grid. A unit that is not in it changes nothing.
pub fn remove(grid grid: Grid, unit_id unit_id: Int) -> Grid {
  todo as "takes a unit out"
}

/// The ids of the units at most `range` metres from `centre`, in no particular
/// order. It reads only the cells that can hold such a unit.
pub fn near(
  grid grid: Grid,
  centre centre: Position,
  range range: Float,
) -> List(Int) {
  todo as "the units near a position"
}
