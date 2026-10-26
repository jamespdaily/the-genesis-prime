//// The shared table of the one-process-per-unit prototype: every unit's
//// position row and grid-cell row, in one unnamed ETS table that every
//// process reads and only the owning unit writes. The table is generic in the
//// mailbox of the unit processes, so this module does not depend on them.
////
//// The rows live in an ordered set, with a unit's position row under the key
//// `{position_key, id}` and its cell row under `{cell_key, kind, x, y, id}`, so
//// every row of one kind in one cell is found by a key prefix, no search reads
//// the whole table, and a search for one kind never reads another kind's rows.

import genesis_prime/topology/grid.{type Cell}
import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/unit.{type Kind}
import genesis_prime/topology/update.{type Delivery}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/list
import gleam/option.{type Option}

/// An ETS table of unit rows whose owners receive `mailbox` messages.
pub type Table(mailbox)

/// What the table knows of one unit: where it is, how to message the process
/// that owns it, and, for a player's unit, the connection to tell what
/// happens in its range.
pub type Row(mailbox) {
  Row(
    unit_id: Int,
    kind: Kind,
    position: Position,
    owner: Subject(mailbox),
    connection: Option(Subject(Delivery)),
  )
}

/// Creates an unnamed public table with read and write concurrency, owned by
/// the calling process; it is deleted when that process exits.
@external(erlang, "topology_ffi", "table_new")
pub fn new() -> Table(mailbox)

/// Writes a unit's position row and its cell row, filed under the unit's kind,
/// and removes the cell row it had before when the unit has changed cell. Only the unit's own process
/// calls this for its unit.
pub fn write(
  table table: Table(mailbox),
  row row: Row(mailbox),
  cell_size cell_size: Float,
) -> Nil {
  case find(table:, unit_id: row.unit_id) {
    Ok(old) -> {
      let old_cell = cell_of(row: old, cell_size:)
      case old_cell == cell_of(row:, cell_size:) {
        True -> Nil
        False ->
          delete(
            table,
            cell_key(cell: old_cell, kind: row.kind, unit_id: row.unit_id),
          )
      }
    }
    Error(Nil) -> Nil
  }
  let cell = cell_of(row:, cell_size:)
  insert(table, PositionKey(row.unit_id), row)
  insert(table, cell_key(cell:, kind: row.kind, unit_id: row.unit_id), row)
}

/// Removes a unit's rows when `owner` is still the process that owns them. A
/// unit that has been rebuilt under a new process keeps its new rows.
pub fn delete_unit(
  table table: Table(mailbox),
  unit_id unit_id: Int,
  owner owner: Pid,
  cell_size cell_size: Float,
) -> Nil {
  case find(table:, unit_id:) {
    Ok(row) -> {
      delete_owned(
        table,
        cell_key(cell: cell_of(row:, cell_size:), kind: row.kind, unit_id:),
        owner,
      )
      delete_owned(table, PositionKey(unit_id), owner)
    }
    Error(Nil) -> Nil
  }
}

/// One unit's row, or an error when it has none.
pub fn find(
  table table: Table(mailbox),
  unit_id unit_id: Int,
) -> Result(Row(mailbox), Nil) {
  lookup(table, PositionKey(unit_id))
}

/// The rows of the units of one kind at most `range` metres from `centre`,
/// from the cells that can hold one. Rows of the other kind are not read.
pub fn near(
  table table: Table(mailbox),
  centre centre: Position,
  range range: Float,
  cell_size cell_size: Float,
  kind kind: Kind,
) -> List(Row(mailbox)) {
  grid.cells_near(centre, range, cell_size)
  |> list.flat_map(fn(cell) { cell_rows(table, kind, cell.x, cell.y) })
  |> list.filter(fn(row) { position.within(row.position, centre, range) })
}

/// The cell a row is filed under.
fn cell_of(row row: Row(mailbox), cell_size cell_size: Float) -> Cell {
  grid.cell_of(row.position, cell_size)
}

/// The words of memory the table holds.
@external(erlang, "topology_ffi", "table_memory_words")
pub fn memory_words(table: Table(mailbox)) -> Int

/// The key of a row in the table: a unit's position row, or its row in one
/// cell, where cell rows are told apart by the unit's kind.
type Key {
  PositionKey(unit_id: Int)
  CellKey(kind: Kind, x: Int, y: Int, unit_id: Int)
}

fn cell_key(cell cell: Cell, kind kind: Kind, unit_id unit_id: Int) -> Key {
  CellKey(kind:, x: cell.x, y: cell.y, unit_id:)
}

@external(erlang, "topology_ffi", "table_insert")
fn insert(table: Table(mailbox), key: Key, row: Row(mailbox)) -> Nil

@external(erlang, "topology_ffi", "table_delete")
fn delete(table: Table(mailbox), key: Key) -> Nil

@external(erlang, "topology_ffi", "table_delete_owned")
fn delete_owned(table: Table(mailbox), key: Key, owner: Pid) -> Nil

@external(erlang, "topology_ffi", "table_lookup")
fn lookup(table: Table(mailbox), key: Key) -> Result(Row(mailbox), Nil)

@external(erlang, "topology_ffi", "table_cell_rows")
fn cell_rows(
  table: Table(mailbox),
  kind: Kind,
  x: Int,
  y: Int,
) -> List(Row(mailbox))
