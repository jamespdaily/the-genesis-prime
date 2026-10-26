//// The server's entry point.

import envoy
import genesis_prime/database/pool
import genesis_prime/server
import genesis_prime/shutdown
import genesis_prime/table
import genesis_prime/table/loader/requirement
import genesis_prime/telemetry/log
import genesis_prime/telemetry/snapshot
import gleam/erlang/atom
import gleam/erlang/node
import gleam/erlang/process
import gleam/erlang/reference

/// The name of a node that is not alive: the one `node()` returns when the
/// VM was started without `-name` or `-sname` (Erlang reference manual,
/// `erlang:node/0`).
const node_without_distribution = "nonode@nohost"

/// How long connections have to close once a stop begins, and how long the
/// saving workers have to flush, in milliseconds. 10 seconds each; no
/// measurement chose them.
const drain_deadline_ms = 10_000

const flush_deadline_ms = 10_000

/// Starts the server's supervision tree, then keeps the calling process alive
/// while the tree runs, until SIGTERM stops the server in order and ends the
/// node. The server runs as one node and uses no Erlang distribution, so it
/// stops at once, saying so, when the VM runs it. The database pool's settings
/// come from PGHOST, PGPORT, PGUSER, PGDATABASE and PGPASSWORD, and the game
/// tables from the folder named by GENESIS_TABLE_DIR; the server stops at once,
/// saying which is missing or wrong, when one it needs is, or when a table
/// does not load. Debug lines are written when GENESIS_DEBUG is 1, and not
/// otherwise.
pub fn main() -> Nil {
  let node_name = atom.to_string(node.name(node.self()))
  case node_name == node_without_distribution {
    True -> Nil
    False ->
      panic as {
        "Erlang distribution is on (this node is named "
        <> node_name
        <> "); the server runs as one node and uses none, so start it without -name or -sname"
      }
  }
  let pool_settings = case
    pool.from_environment(
      name: process.new_name("database_pool"),
      get: envoy.get,
    )
  {
    Ok(settings) -> settings
    Error(error) -> panic as pool.describe(error)
  }
  log.configure(debug: envoy.get("GENESIS_DEBUG") == Ok("1"))
  let table_folder = case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  let shutdown_settings = shutdown.new(drain_deadline_ms:, flush_deadline_ms:)
  let settings =
    server.Settings(
      pool: pool_settings,
      tables: server.TableSettings(
        key: reference.new(),
        folder: table_folder,
        entries: table.entries(),
        requirements: requirement.all(),
      ),
      shutdown: shutdown_settings,
      snapshot: snapshot.settings(process.new_name("snapshot")),
    )
  let started = case server.start(settings) {
    Ok(started) -> started
    Error(error) -> panic as server.describe(error)
  }
  shutdown.run(tree: started.pid, settings: shutdown_settings)
}
