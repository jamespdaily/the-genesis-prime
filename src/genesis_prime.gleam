//// Starts the server: it loads the client's game tables from the folder named
//// by GENESIS_TABLE_DIR, stopping at once with the reason when one does not
//// load, then starts the supervision tree, with the database named by PGHOST,
//// PGPORT, PGUSER, PGPASSWORD and PGDATABASE, and keeps the node alive. It
//// serves no client.

import envoy
import genesis_prime/server
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/io
import gleam/list

pub fn main() -> Nil {
  let folder = case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  let entries = table.entries()
  case
    store.load(under: reference.new(), from: folder, entries:, requirements: [])
  {
    Ok(_tables) -> Nil
    Error(error) -> panic as store.describe(error)
  }
  let assert Ok(_) = server.start(settings: settings())
    as "the supervision tree did not start"
  io.println(
    "the server loaded "
    <> int.to_string(list.length(entries))
    <> " game tables and serves no client",
  )
  process.sleep_forever()
}

/// The tree's settings: the database from the environment, with Postgres's
/// own defaults for what is not set, and a fresh name for each child.
fn settings() -> server.Settings {
  todo as "the build follows the shape commit"
}
