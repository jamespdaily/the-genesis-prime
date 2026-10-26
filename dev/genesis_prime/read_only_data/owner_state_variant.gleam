//// The tables in each owner's own state: every process that reads a table
//// holds a copy of it, as a tuple of rows. A load starts the holder processes
//// and gives each its own copy; a reader opened later takes its own copy too.

import genesis_prime/read_only_data/client_table.{type PerTable}
import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/table_data.{type Source, type Table}
import genesis_prime/read_only_data/variant.{
  type Memory, type Variant, Loaded, Memory, Reader, Variant,
}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/string

/// A process holding a copy of the three tables, and the subject that tells it
/// to stop.
type Holder {
  Holder(pid: Pid, stop: Subject(Nil))
}

/// The variant: a load builds each table's tuple once in the calling process
/// and starts the holders, each receiving its copy.
pub fn variant() -> Variant {
  Variant(name: "owner state", load: fn(source: Source, holders) {
    let tables = client_table.map(source, table_data.table_of)
    let started =
      list.repeat(Nil, holders)
      |> list.map(fn(_) { start_holder(tables) })
    Loaded(
      memory: fn() { memory(started) },
      open_reader: fn() {
        Reader(read_all: fn(stream) { read_all(tables, stream) })
      },
      stop: fn() { list.each(started, stop_holder) },
    )
  })
}

/// Starts a process that holds `tables` until told to stop, and waits until it
/// holds them.
fn start_holder(tables: PerTable(Table)) -> Holder {
  let ready = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let stop = process.new_subject()
      process.send(ready, stop)
      process.receive_forever(stop)
      // The tables are used after the wait so the process keeps them. One
      // row each is enough; measuring a whole copy here would walk every
      // term and outlast the stop's deadline.
      let _rows =
        client_table.map(tables, fn(table) { table_data.row_at(table, 1) })
      Nil
    })
  let assert Ok(stop) = process.receive(ready, 120_000)
    as "a holder did not start"
  Holder(pid:, stop:)
}

/// Stops a holder and waits until it has gone.
fn stop_holder(holder: Holder) -> Nil {
  let monitor = process.monitor(holder.pid)
  process.send(holder.stop, Nil)
  let assert Ok(_down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 60_000)
    as "a holder did not stop"
  Nil
}

/// The memory of the holders: after a garbage collection of each, the process
/// memory of all of them added up.
fn memory(holders: List(Holder)) -> Memory {
  list.each(holders, fn(holder) { measurement.collect_process(holder.pid) })
  let each =
    list.map(holders, fn(holder) {
      measurement.process_memory_bytes(holder.pid)
    })
  Memory(
    bytes: list.fold(each, 0, int.add),
    detail: "process memory of "
      <> int.to_string(list.length(holders))
      <> " holders after a garbage collection, bytes each "
      <> string.join(list.map(each, int.to_string), ", ")
      <> "; runtime binary memory "
      <> int.to_string(measurement.binary_memory_bytes())
      <> " bytes, shared by every variant",
  )
}

/// Reads each entry of the stream from its table's tuple and checks the row.
fn read_all(tables: PerTable(Table), stream: BitArray) -> Int {
  read_from(tables:, stream:, checked: 0)
}

fn read_from(
  tables tables: PerTable(Table),
  stream stream: BitArray,
  checked checked: Int,
) -> Int {
  case stream {
    <<table:8, id:24, rest:bits>> -> {
      let row =
        table_data.row_at(client_table.at(per_table: tables, index: table), id)
      let assert True = table_data.id_of(row) == id
        as "a row has another id than the one asked for"
      read_from(tables:, stream: rest, checked: checked + 1)
    }
    _ -> checked
  }
}
