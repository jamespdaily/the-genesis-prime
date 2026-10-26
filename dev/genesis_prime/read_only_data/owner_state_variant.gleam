//// The tables in each owner's own state: every process that reads a table
//// holds a copy of it, as a tuple of rows. A load starts the holder processes
//// and gives each its own copy; a reader opened later takes its own copy too.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/table_data.{type Source, type Table}
import genesis_prime/read_only_data/variant.{type Variant}
import gleam/erlang/process.{type Pid, type Subject}

/// A process holding a copy of the three tables, and the subject that tells it
/// to stop.
type Holder {
  Holder(pid: Pid, stop: Subject(Nil))
}

/// The variant: a load builds each table's tuple once in the calling process
/// and starts the holders, each receiving its copy.
pub fn variant() -> Variant {
  todo as "body in the build commit"
}

/// Starts a process that holds `tables` until told to stop, and waits until it
/// holds them.
fn start_holder(tables: PerTable(Table)) -> Holder {
  todo as "body in the build commit"
}

/// Stops a holder and waits until it has gone.
fn stop_holder(holder: Holder) -> Nil {
  todo as "body in the build commit"
}

/// The memory of the holders: after a garbage collection of each, the process
/// memory of all of them added up.
fn memory(holders: List(Holder)) -> variant.Memory {
  todo as "body in the build commit"
}

/// Reads each entry of the stream from its table's tuple and checks the row.
fn read_all(tables: PerTable(Table), stream: BitArray) -> Int {
  todo as "body in the build commit"
}
