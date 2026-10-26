//// The tables in ETS: one `set` table per game table, keyed by the id in the
//// row's first element, with `read_concurrency`, owned by a process started
//// before anything reads. The tables are public so the loading process can
//// insert the rows without sending them to the owner; production would use
//// protected tables loaded by the owner, and a read costs the same.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/table_data.{type Row, type Source}
import genesis_prime/read_only_data/variant.{
  type Memory, type Variant, Loaded, Memory, Reader, Variant,
}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/string

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
  Variant(name: "ETS set", load: fn(source: Source, _holders) {
    let owner = start_owner()
    insert_rows(owner.tables.creature2, source.creature2)
    insert_rows(owner.tables.spell4, source.spell4)
    insert_rows(owner.tables.spline2node, source.spline2node)
    Loaded(
      memory: fn() { memory(owner) },
      open_reader: fn() {
        Reader(read_all: fn(stream) { read_all(owner.tables, stream) })
      },
      stop: fn() { stop_owner(owner) },
    )
  })
}

/// Starts the owner process and waits until it has made its three tables.
fn start_owner() -> Owner {
  let made = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let stop = process.new_subject()
      let tables =
        client_table.map(client_table.measured(), fn(_) { new_table() })
      process.send(made, #(tables, stop))
      process.receive_forever(stop)
    })
  let assert Ok(#(tables, stop)) = process.receive(made, 30_000)
    as "the ETS owner did not make its tables"
  Owner(pid:, tables:, stop:)
}

/// Stops the owner, which deletes its tables, and waits until it has gone.
fn stop_owner(owner: Owner) -> Nil {
  let monitor = process.monitor(owner.pid)
  process.send(owner.stop, Nil)
  let assert Ok(_down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 60_000)
    as "the ETS owner did not stop"
  Nil
}

/// The memory of the tables: `ets:info(Table, memory)` summed over the three,
/// in words, as bytes.
fn memory(owner: Owner) -> Memory {
  let words =
    client_table.map(owner.tables, table_memory_words) |> client_table.to_list
  let bytes = list.fold(words, 0, int.add) * measurement.word_bytes()
  Memory(
    bytes:,
    detail: "ets:info(Table, memory) words per table "
      <> string.join(list.map(words, int.to_string), ", ")
      <> "; runtime binary memory "
      <> int.to_string(measurement.binary_memory_bytes())
      <> " bytes, shared by every variant",
  )
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
  read_from(tables:, stream:, checked: 0)
}

fn read_from(
  tables tables: PerTable(EtsTable),
  stream stream: BitArray,
  checked checked: Int,
) -> Int {
  case stream {
    <<table:8, id:24, rest:bits>> -> {
      let assert [row] =
        lookup(client_table.at(per_table: tables, index: table), id)
        as "a table does not hold exactly one row for an id"
      let assert True = table_data.id_of(row) == id
        as "a row has another id than the one asked for"
      read_from(tables:, stream: rest, checked: checked + 1)
    }
    _ -> checked
  }
}
