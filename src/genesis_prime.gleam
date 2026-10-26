//// The server's entry point.

import envoy
import genesis_prime/database/pool
import genesis_prime/login/random_source.{type RandomSource}
import genesis_prime/login/service
import genesis_prime/message/bit_stream.{Endpoint}
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
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string

/// The name of a node that is not alive: the one `node()` returns when the
/// VM was started without `-name` or `-sname` (Erlang reference manual,
/// `erlang:node/0`).
const node_without_distribution = "nonode@nohost"

/// How long connections have to close once a stop begins, and how long the
/// saving workers have to flush, in milliseconds. 10 seconds each; no
/// measurement chose them.
const drain_deadline_ms = 10_000

const flush_deadline_ms = 10_000

/// The ports of the client's own servers: the STS service it logs in to first
/// (the code at `0x14000d3ca`, the AuthNc address's port) and the auth server
/// (the code at `0x140c3adbc`).
const default_sts_port = 6600

const default_auth_port = 23_115

/// What the auth login hands a client to when GENESIS_GAME_ADDRESS,
/// GENESIS_GAME_PORT and GENESIS_REALM_NAME do not say: the game listener's
/// address and port are the server's own choice, which no client data sets, so
/// these are the defaults a development machine runs.
const default_game_address = "127.0.0.1"

const default_game_port = 24_000

const default_realm_name = "GenesisPrime"

/// Starts the released server: the settings `release_settings` reads from the
/// environment, run until SIGTERM stops the server in order.
pub fn main() -> Nil {
  run(settings: release_settings(get: envoy.get))
}

/// The settings of the released server: everything `settings` reads from the
/// environment, and the operating system's strong random source, which no
/// setting changes.
pub fn release_settings(
  get get: fn(String) -> Result(String, Nil),
) -> server.Settings {
  settings(get:, random: random_source.Strong)
}

/// The settings the server starts with, read from the environment through `get`,
/// with the login drawing its random bytes from `random`. The database pool's
/// settings come from PGHOST, PGPORT, PGUSER, PGDATABASE and PGPASSWORD, and the
/// game tables from the folder named by GENESIS_TABLE_DIR; the server stops at
/// once, saying which is missing or wrong, when one it needs is. The login's
/// ports come from GENESIS_STS_PORT and GENESIS_AUTH_PORT (6600 and 23115 when
/// unset), where 0 takes a free port; GENESIS_GAME_ADDRESS, GENESIS_GAME_PORT
/// and GENESIS_REALM_NAME name what a client that logged in is handed to.
pub fn settings(
  get get: fn(String) -> Result(String, Nil),
  random random: RandomSource,
) -> server.Settings {
  let pool_settings = case
    pool.from_environment(name: process.new_name("database_pool"), get:)
  {
    Ok(settings) -> settings
    Error(error) -> panic as pool.describe(error)
  }
  let table_folder = case get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  server.Settings(
    pool: pool_settings,
    tables: server.TableSettings(
      key: reference.new(),
      folder: table_folder,
      entries: table.entries(),
      requirements: requirement.all(),
    ),
    shutdown: shutdown.new(drain_deadline_ms:, flush_deadline_ms:),
    snapshot: snapshot.settings(process.new_name("snapshot")),
    login: service.settings(
      sts_port: port(get, "GENESIS_STS_PORT", default_sts_port),
      auth_port: port(get, "GENESIS_AUTH_PORT", default_auth_port),
      game_server: Endpoint(
        address: address(get, "GENESIS_GAME_ADDRESS", default_game_address),
        port: port(get, "GENESIS_GAME_PORT", default_game_port),
      ),
      realm_name: get("GENESIS_REALM_NAME")
        |> result.unwrap(default_realm_name),
      expected_files_digest: None,
      random:,
    ),
  )
}

/// Starts the server's supervision tree with `settings`, then keeps the calling
/// process alive while the tree runs, until SIGTERM stops the server in order
/// and ends the node. The server runs as one node and uses no Erlang
/// distribution, so it stops at once, saying so, when the VM runs it, and when
/// a table does not load. Debug lines are written when GENESIS_DEBUG is 1, and
/// not otherwise.
pub fn run(settings settings: server.Settings) -> Nil {
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
  log.configure(debug: envoy.get("GENESIS_DEBUG") == Ok("1"))
  let started = case server.start(settings) {
    Ok(started) -> started
    Error(error) -> panic as server.describe(error)
  }
  shutdown.run(tree: started.pid, settings: settings.shutdown)
}

/// A port from the environment through `get`, or its default when the variable
/// is not set; the server stops at once, saying so, when the variable is not a
/// port.
fn port(
  get: fn(String) -> Result(String, Nil),
  variable: String,
  default: Int,
) -> Int {
  case get(variable) {
    Error(Nil) -> default
    Ok(text) ->
      case int.parse(text) {
        Ok(number) if number >= 0 && number <= 65_535 -> number
        Ok(_) | Error(Nil) ->
          panic as { variable <> " is " <> text <> ", which is not a port" }
      }
  }
}

/// An IPv4 address from the environment through `get` as the number the client
/// reads (127.0.0.1 is 0x7F000001), or the default's when the variable is not
/// set; the server stops at once, saying so, when the variable is not an
/// address.
fn address(
  get: fn(String) -> Result(String, Nil),
  variable: String,
  default: String,
) -> Int {
  let text = get(variable) |> result.unwrap(default)
  let parts = string.split(text, ".") |> list.try_map(int.parse)
  case parts {
    Ok([first, second, third, fourth])
      if first >= 0
      && first <= 255
      && second >= 0
      && second <= 255
      && third >= 0
      && third <= 255
      && fourth >= 0
      && fourth <= 255
    -> first * 16_777_216 + second * 65_536 + third * 256 + fourth
    Ok(_) | Error(Nil) ->
      panic as { variable <> " is " <> text <> ", which is not an IPv4 address" }
  }
}
