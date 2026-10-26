//// The tables in ETS: one `set` table per game table, keyed by the id in the
//// row's first element, with `read_concurrency`, owned by a process started
//// before anything reads. The tables are public so the loading process can
//// insert; a protected table reads the same.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/table_data.{type Row, type Source}
import genesis_prime/read_only_data/variant.{type Variant}
import gleam/erlang/process.{type Pid, type Subject}

/// An ETS table.
type EtsTable

/// The process that owns the tables, the tables it made, and the subject that
/// tells it to stop.
type Owner {
  Owner(pid: Pid, tables: PerTable(EtsTable), stop: Subject(Nil))
}

/// The variant: each load starts an owner, which makes the three tables, and
/// the loading process inserts the rows.
pub fn variant() -> Variant {
  todo as "body in the build commit"
}

/// Starts the owner process and waits until it has made its three tables.
fn start_owner() -> Owner {
  todo as "body in the build commit"
}

/// Stops the owner, which deletes its tables, and waits until it has gone.
fn stop_owner(owner: Owner) -> Nil {
  todo as "body in the build commit"
}

/// The memory of the tables: `ets:info(Table, memory)` summed over the three,
/// in words, as bytes.
fn memory(owner: Owner) -> variant.Memory {
  todo as "body in the build commit"
}

/// Makes a `set` table with `read_concurrency`, public, keyed on element 1.
@external(erlang, "read_only_data_ffi", "new_table")
fn new_table() -> EtsTable

/// Inserts every row.
@external(erlang, "read_only_data_ffi", "insert_rows")
fn insert_rows(table: EtsTable, rows: List(Row)) -> Nil

/// The rows stored under an id: one, since the table is a set.
@external(erlang, "ets", "lookup")
fn lookup(table: EtsTable, id: Int) -> List(Row)

/// The words of memory the table holds.
@external(erlang, "read_only_data_ffi", "table_memory_words")
fn table_memory_words(table: EtsTable) -> Int

/// Reads each entry of the stream from its table and checks the row.
fn read_all(tables: PerTable(EtsTable), stream: BitArray) -> Int {
  todo as "body in the build commit"
}
