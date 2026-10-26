//// Prints the coverage measure: for each engine, the types the client's
//// tables use, heaviest first, against the types the engine handles.
////
//// `gleam run -m genesis_prime/coverage` loads the client's tables from
//// `GENESIS_TABLE_DIR` (else `GENESIS_HOME`/tables, else
//// `~/.genesis-prime/tables`) and prints a Markdown checklist per engine. It
//// exits with 1 when the tables do not load or an engine declares a type no
//// row uses.

import envoy
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine
import genesis_prime/coverage/measurement.{type Measurement, Measured}
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/reference
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

/// Runs the measure.
pub fn main() -> Nil {
  let folder = tables_folder()
  case table.load(under: reference.new(), from: folder) {
    Error(error) -> {
      io.println(
        "the client's tables did not load from "
        <> folder
        <> ": "
        <> describe(error)
        <> "; run python3.13 -I setup_check/extract_tables.py",
      )
      halt(1)
    }
    Ok(tables) -> {
      let measurements =
        list.map(engine.all(), fn(declared) {
          measurement.measure(declared, tables)
        })
      store.unload(tables)
      io.println(checklist.totals(measurements))
      io.println("")
      io.println(checklist.render(measurements))
      case breaches(measurements) {
        [] -> Nil
        found -> {
          list.each(found, io.println)
          halt(1)
        }
      }
    }
  }
}

/// A line for each engine that declares a type no row uses.
fn breaches(measurements: List(Measurement)) -> List(String) {
  list.filter_map(measurements, fn(measured) {
    case measured {
      Measured(engine:, breaches: [_, ..] as unused, ..) ->
        Ok(
          engine.name
          <> " declares types no row uses: "
          <> string.join(list.map(unused, int.to_string), ", "),
        )
      Measured(breaches: [], ..) | measurement.Unmeasured(..) -> Error(Nil)
    }
  })
}

fn tables_folder() -> String {
  case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      case envoy.get("GENESIS_HOME"), envoy.get("HOME") {
        Ok(home), _ -> home <> "/tables"
        Error(Nil), Ok(home) -> home <> "/.genesis-prime/tables"
        Error(Nil), Error(Nil) -> "tables"
      }
  }
}

fn describe(error: store.LoadError) -> String {
  case error {
    store.TableFileUnreadable(file:, reason:) ->
      file <> ".tbl cannot be read: " <> simplifile.describe_error(reason)
    store.TableFileInvalid(table:, ..) ->
      table <> ".tbl is not accepted as the " <> table <> " table"
    store.RowMissing(from_table:, column:, to_table:, id:) ->
      from_table
      <> "."
      <> column
      <> " names "
      <> to_table
      <> " id "
      <> int.to_string(id)
      <> ", which has no row"
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil
