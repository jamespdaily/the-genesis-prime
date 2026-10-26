//// What loading all of the client's game tables into persistent terms costs:
//// the time of a load (five loads, the median counts) and what the loaded
//// tables hold in memory.
////
//// Run it with `gleam run -m genesis_prime/table_load_cost` on a machine with
//// nothing else heavy running, after `setup_check/extract_tables.py`. It reads
//// the folder `GENESIS_TABLE_DIR` names (default `~/.genesis-prime/tables`).
//// Memory is read after the first load and a garbage collection of every
//// process: the bytes persistent terms hold (`persistent_term:info()`), the
//// runtime's total and binary memory, and the memory the operating system
//// reports for the VM, each over its value before the load.

import genesis_prime/read_only_data/measurement
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/reference
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

/// How many times a load is timed.
const load_runs = 5

/// The numbers read before and after a load.
type Counters {
  Counters(terms: Int, binaries: Int, total: Int, resident: Int)
}

fn counters() -> Counters {
  collect_all()
  Counters(
    terms: persistent_term_bytes(),
    binaries: measurement.binary_memory_bytes(),
    total: total_memory(),
    resident: resident_bytes(),
  )
}

/// Runs the measurement and prints it.
pub fn main() -> Nil {
  let folder = case getenv("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      case getenv("HOME") {
        Ok(home) -> home <> "/.genesis-prime/tables"
        Error(Nil) -> "tables"
      }
  }
  io.println("tables folder: " <> folder)
  let before = counters()
  let times =
    int.range(from: 0, to: load_runs, with: [], run: fn(times, run) {
      let started = measurement.monotonic_nanoseconds()
      let assert Ok(tables) = table.load(under: reference.new(), from: folder)
        as "the client's tables did not load; run setup_check/extract_tables.py"
      let elapsed = measurement.monotonic_nanoseconds() - started
      case run {
        0 -> print_memory(before, counters())
        _ -> Nil
      }
      store.unload(tables)
      [elapsed, ..times]
    })
    |> list.reverse
  io.println(
    "load times (ms): "
    <> string.join(list.map(times, milliseconds), ", ")
    <> "; median "
    <> milliseconds(median(times)),
  )
}

fn print_memory(before: Counters, after: Counters) -> Nil {
  io.println(
    "after the first load and a collection of every process, over before it:",
  )
  io.println("  persistent terms  " <> megabytes(after.terms - before.terms))
  io.println(
    "  binary memory     " <> megabytes(after.binaries - before.binaries),
  )
  io.println("  runtime total     " <> megabytes(after.total - before.total))
  io.println(
    "  VM in the OS      " <> megabytes(after.resident - before.resident),
  )
}

fn median(values: List(Int)) -> Int {
  let sorted = list.sort(values, int.compare)
  case list.drop(sorted, list.length(sorted) / 2) {
    [middle, ..] -> middle
    [] -> 0
  }
}

fn milliseconds(nanoseconds: Int) -> String {
  float.to_string(float.to_precision(
    int.to_float(nanoseconds) /. 1_000_000.0,
    1,
  ))
}

fn megabytes(bytes: Int) -> String {
  float.to_string(float.to_precision(int.to_float(bytes) /. 1_048_576.0, 1))
  <> " MB"
}

@external(erlang, "read_only_data_ffi", "persistent_term_bytes")
fn persistent_term_bytes() -> Int

@external(erlang, "table_load_cost_ffi", "total_memory")
fn total_memory() -> Int

@external(erlang, "table_load_cost_ffi", "collect_all")
fn collect_all() -> Nil

@external(erlang, "table_load_cost_ffi", "resident_bytes")
fn resident_bytes() -> Int

@external(erlang, "table_load_cost_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)
