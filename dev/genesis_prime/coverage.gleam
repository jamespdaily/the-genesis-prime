//// Prints the coverage measure: for each engine, the types the client's
//// tables use, heaviest first, against the types the engine handles.
////
//// `gleam run -m genesis_prime/coverage` loads the client's tables from
//// `GENESIS_TABLE_DIR` (else `GENESIS_HOME`/tables, else
//// `~/.genesis-prime/tables`) and prints a Markdown checklist per engine. It
//// exits with 1 when the tables do not load or an engine declares a type no
//// row uses.
////
//// It then prints the coverage of the world's spawns, a line for each world: how
//// many start as fight creatures, how many NonPlayer rows are left out and why,
//// and how many rows each other entity type has (genesis_prime/world_map/spawn,
//// the same function the server's load logs). The spawns are those of the play
//// database (PGHOST, PGPORT, PGUSER, PGPASSWORD and PGDATABASE); when it cannot be
//// read the tool says so and goes on.

import genesis_prime/content/spawn as content_spawn
import genesis_prime/coverage/checklist
import genesis_prime/coverage/engine
import genesis_prime/coverage/measurement.{type Measurement, Measured}
import genesis_prime/dev_database
import genesis_prime/dev_exit
import genesis_prime/store/worker
import genesis_prime/table
import genesis_prime/table/loader/store
import genesis_prime/table_folder
import genesis_prime/world_map/spawn
import gleam/erlang/reference
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

/// Runs the measure.
pub fn main() -> Nil {
  let folder = table_folder.path()
  case table.load(under: reference.new(), from: folder) {
    Error(error) -> {
      io.println(
        "the client's tables did not load from "
        <> folder
        <> ": "
        <> describe(error)
        <> "; run python3.13 -I setup_check/extract_tables.py",
      )
      dev_exit.halt(1)
    }
    Ok(tables) -> {
      let measurements =
        list.map(engine.all(), fn(declared) {
          measurement.measure(declared, tables)
        })
      let spawns = spawn_coverage(tables:)
      store.unload(tables)
      io.println(checklist.totals(measurements))
      io.println("")
      io.println(checklist.render(measurements))
      io.println("")
      io.println(spawns)
      case breaches(measurements) {
        [] -> Nil
        found -> {
          list.each(found, io.println)
          dev_exit.halt(1)
        }
      }
    }
  }
}

/// The coverage of the play database's spawns, a line for each world, or why it
/// cannot be measured, from the client's tables, which hold every table the
/// selection reads.
fn spawn_coverage(tables tables: store.Tables) -> String {
  case dev_database.connect() {
    Error(failure) ->
      "The spawn coverage needs the play database: "
      <> dev_database.describe(failure, "read the spawns")
    Ok(db) ->
      case content_spawn.rows(db) {
        Error(error) ->
          "The spawn coverage needs the spawn table (run the migrations and the import on the play database): "
          <> worker.describe_query_error(error)
        Ok(rows) ->
          string.join(
            [
              "Spawns that start, by world:",
              ..list.map(spawn.select(rows:, tables:).coverage, fn(coverage) {
                "- " <> spawn.describe_coverage(coverage:)
              })
            ],
            "\n",
          )
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
    store.DerivationFailed(name:, reason:) ->
      name <> " cannot be built: " <> reason
  }
}
