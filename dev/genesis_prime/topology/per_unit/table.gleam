//// The shared table of the one-process-per-unit prototype: every unit's
//// position row and grid-cell row, in one unnamed ETS table that every
//// process reads and only the owning unit writes. The table is generic in the
//// mailbox of the unit processes, so this module does not depend on them.
////
//// The rows live in an ordered set, with a unit's position row under the key
//// `{position, id}` and its cell row under `{cell, x, y, id}`, so every row of
//// one cell is found by a key prefix and no search reads the whole table.

import genesis_prime/topology/grid.{type Cell}
import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/unit.{type Kind}
import genesis_prime/topology/update.{type Delivery}
import gleam/erlang/process.{type Pid, type Subject}
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

/// Writes a unit's position row and its cell row, and removes the cell row it
/// had before when the unit has changed cell. Only the unit's own process
/// calls this for its unit.
pub fn write(
  table: Table(mailbox),
  row: Row(mailbox),
  cell_size: Float,
) -> Nil {
  todo as "body in the build commit"
}

/// Removes a unit's rows when `owner` is still the process that owns them. A
/// unit that has been rebuilt under a new process keeps its new rows.
pub fn delete_unit(
  table: Table(mailbox),
  unit_id: Int,
  owner: Pid,
  cell_size: Float,
) -> Nil {
  todo as "body in the build commit"
}

/// One unit's row, or an error when it has none.
pub fn find(table: Table(mailbox), unit_id: Int) -> Result(Row(mailbox), Nil) {
  todo as "body in the build commit"
}

/// The rows of the units at most `range` metres from `position`, from the
/// cells that can hold one.
pub fn near(
  table: Table(mailbox),
  position: Position,
  range: Float,
  cell_size: Float,
) -> List(Row(mailbox)) {
  todo as "body in the build commit"
}

/// The cell a row is filed under.
pub fn cell_of(row: Row(mailbox), cell_size: Float) -> Cell {
  todo as "body in the build commit"
}

/// The words of memory the table holds.
@external(erlang, "topology_ffi", "table_memory_words")
pub fn memory_words(table: Table(mailbox)) -> Int
