//// The spatial index of a map: the units on it by cell, so the units near a
//// position are found by reading only the cells that can hold one in range.
//// Pure.
////
//// A unit id here is a plain `Int`, a named hot path under the typed-id rule of
//// the writing-gleam skill: the index is the code every look-up passes
//// through, as it was in the topology trial (`id_cost` measured a typed id at
//// about 5% of a hot path's time).

import genesis_prime/map/position.{type Position, Position}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

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
  Grid(
    cell_size: Float,
    cells: Dict(Cell, List(Int)),
    positions: Dict(Int, Position),
  )
}

/// An empty grid whose cells are `cell_size` metres wide. A cell as wide as the
/// range searched means a search reads at most 27 cells.
pub fn new(cell_size cell_size: Float) -> Grid {
  Grid(cell_size:, cells: dict.new(), positions: dict.new())
}

/// The cell a position lies in, for cells `cell_size` metres wide.
pub fn cell_of(
  position position: Position,
  cell_size cell_size: Float,
) -> Cell {
  Cell(
    x: float.truncate(float.floor(position.x /. cell_size)),
    y: float.truncate(float.floor(position.y /. cell_size)),
    z: float.truncate(float.floor(position.z /. cell_size)),
  )
}

/// Every cell that can hold a position within `range` metres of `position`,
/// for cells `cell_size` metres wide.
pub fn cells_near(
  position position: Position,
  range range: Float,
  cell_size cell_size: Float,
) -> List(Cell) {
  let low =
    cell_of(
      position: Position(
        x: position.x -. range,
        y: position.y -. range,
        z: position.z -. range,
      ),
      cell_size:,
    )
  let high =
    cell_of(
      position: Position(
        x: position.x +. range,
        y: position.y +. range,
        z: position.z +. range,
      ),
      cell_size:,
    )
  use x <- list.flat_map(ascending(low.x, high.x))
  use y <- list.flat_map(ascending(low.y, high.y))
  use z <- list.map(ascending(low.z, high.z))
  Cell(x:, y:, z:)
}

/// Adds a unit at a position. A unit already in the grid is moved.
pub fn insert(
  grid grid: Grid,
  unit_id unit_id: Int,
  position position: Position,
) -> Grid {
  let cell = cell_of(position:, cell_size: grid.cell_size)
  let cells = case dict.get(grid.positions, unit_id) {
    Ok(old_position) -> {
      let old_cell = cell_of(position: old_position, cell_size: grid.cell_size)
      case old_cell == cell {
        True -> grid.cells
        False ->
          with_unit(
            cells: without_unit(cells: grid.cells, cell: old_cell, unit_id:),
            cell:,
            unit_id:,
          )
      }
    }
    Error(Nil) -> with_unit(cells: grid.cells, cell:, unit_id:)
  }
  Grid(
    ..grid,
    cells:,
    positions: dict.insert(grid.positions, unit_id, position),
  )
}

/// Takes a unit out of the grid. A unit that is not in it changes nothing.
pub fn remove(grid grid: Grid, unit_id unit_id: Int) -> Grid {
  case dict.get(grid.positions, unit_id) {
    Error(Nil) -> grid
    Ok(position) ->
      Grid(
        ..grid,
        cells: without_unit(
          cells: grid.cells,
          cell: cell_of(position:, cell_size: grid.cell_size),
          unit_id:,
        ),
        positions: dict.delete(grid.positions, unit_id),
      )
  }
}

/// The ids of the units at most `range` metres from `centre`, in no particular
/// order. It reads only the cells that can hold such a unit.
pub fn near(
  grid grid: Grid,
  centre centre: Position,
  range range: Float,
) -> List(Int) {
  cells_near(position: centre, range:, cell_size: grid.cell_size)
  |> list.flat_map(fn(cell) { dict.get(grid.cells, cell) |> result.unwrap([]) })
  |> list.filter(fn(unit_id) {
    case dict.get(grid.positions, unit_id) {
      Ok(unit_position) -> position.within(unit_position, centre, range)
      Error(Nil) -> False
    }
  })
}

/// The cells with a unit taken out of one of them; a cell left empty is
/// removed.
fn without_unit(
  cells cells: Dict(Cell, List(Int)),
  cell cell: Cell,
  unit_id unit_id: Int,
) -> Dict(Cell, List(Int)) {
  case dict.get(cells, cell) {
    Ok(unit_ids) ->
      case list.filter(unit_ids, fn(other) { other != unit_id }) {
        [] -> dict.delete(cells, cell)
        remaining -> dict.insert(cells, cell, remaining)
      }
    Error(Nil) -> cells
  }
}

/// The cells with a unit put in one of them.
fn with_unit(
  cells cells: Dict(Cell, List(Int)),
  cell cell: Cell,
  unit_id unit_id: Int,
) -> Dict(Cell, List(Int)) {
  let unit_ids = dict.get(cells, cell) |> result.unwrap([])
  dict.insert(cells, cell, [unit_id, ..unit_ids])
}

/// The integers from `first` to `last`, ascending.
fn ascending(first: Int, last: Int) -> List(Int) {
  int.range(last, first - 1, [], list.prepend)
}
