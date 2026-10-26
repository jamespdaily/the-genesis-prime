//// The process that owns the one-process-per-unit prototype's table. Units
//// write their own rows; this process creates the table, monitors every unit
//// process and removes the rows of one that died, so the table never holds a
//// dead unit.

import genesis_prime/topology/per_unit/table.{type Table}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/supervision.{type ChildSpecification}

/// Every message the table owner can receive. Its selector covers these and
/// the down messages of the processes it monitors.
pub type Message {
  /// A unit process has written its rows and is to be watched.
  Track(unit_id: Int, owner: Pid)
  /// Asks for the processes now watched, one per live unit.
  TrackedProcesses(reply_with: Subject(List(Pid)))
}

/// What the owner tells whoever starts it: the table, and where to send it
/// messages.
pub type TableOwner(mailbox) {
  TableOwner(table: Table(mailbox), control: Subject(Message))
}

/// The state of the table owner: the table, the cell width its cleanup needs,
/// and the unit each watched process owns.
pub type State(mailbox) {
  State(table: Table(mailbox), cell_size: Float, watched: Dict(Pid, Int))
}

/// The child specification for the table owner. Once the table exists the
/// owner sends a `TableOwner` on `ready`. A restart creates an empty table and
/// sends again, and the units of the old table are not rebuilt by it, so the
/// run that saw it is not measured.
pub fn supervised(
  cell_size: Float,
  ready: Subject(TableOwner(mailbox)),
) -> ChildSpecification(Subject(Message)) {
  todo as "body in the build commit"
}
