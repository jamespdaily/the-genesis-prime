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
import gleam/option.{Some}
import pog

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
  let pool = pog.default_config(process.new_name("database_pool"))
  let pool = from_environment(pool, "PGHOST", pog.host)
  let pool = from_environment(pool, "PGUSER", pog.user)
  let pool = from_environment(pool, "PGDATABASE", pog.database)
  let pool = case envoy.get("PGPORT") {
    Ok(text) ->
      case int.parse(text) {
        Ok(port) -> pog.port(pool, port)
        Error(Nil) -> panic as "PGPORT is not a port number"
      }
    Error(Nil) -> pool
  }
  let pool = case envoy.get("PGPASSWORD") {
    Ok(password) -> pog.password(pool, Some(password))
    Error(Nil) -> pool
  }
  server.Settings(
    pool:,
    store: process.new_name("store"),
    hand_off: process.new_name("hand_off"),
    hand_off_shutdown_ms: 5000,
  )
}

/// The pool's setting from an environment variable, or the pool as it is
/// when the variable is not set.
fn from_environment(
  pool: pog.Config,
  variable: String,
  set: fn(pog.Config, String) -> pog.Config,
) -> pog.Config {
  case envoy.get(variable) {
    Ok(value) -> set(pool, value)
    Error(Nil) -> pool
  }
}
