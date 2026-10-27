//// Starts the server: it loads the client's game tables from the folder named
//// by GENESIS_TABLE_DIR, stopping at once with the reason when one does not
//// load, then starts the supervision tree, with the database named by PGHOST,
//// PGPORT, PGUSER, PGPASSWORD and PGDATABASE, and keeps the node alive. It
//// serves the client's STS and auth logins (`login`) and no game server.

import envoy
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import pog

pub fn main() -> Nil {
  let tables = load_tables()
  start(settings: settings(), tables:)
}

/// Loads the game tables from the folder GENESIS_TABLE_DIR names, once, into
/// their named records; a missing variable or a table that does not load
/// stops the program with the reason. Gives how many tables it loaded.
pub fn load_tables() -> Int {
  let folder = case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  let entries = table.entries()
  case
    store.load(under: reference.new(), from: folder, entries:, requirements: [])
  {
    Ok(_tables) -> list.length(entries)
    Error(error) -> panic as store.describe(error)
  }
}

/// Starts the supervision tree with these settings and keeps the node alive.
pub fn start(settings settings: server.Settings, tables tables: Int) -> Nil {
  let assert Ok(_) = server.start(settings:)
    as "the supervision tree did not start"
  io.println(
    "the server loaded "
    <> int.to_string(tables)
    <> " game tables and serves the STS login on port "
    <> int.to_string(settings.login.sts_port)
    <> " and the auth login on port "
    <> int.to_string(settings.login.auth_port),
  )
  process.sleep_forever()
}

/// The tree's settings: the database from the environment, with Postgres's
/// own defaults for what is not set, and a fresh name for each child.
pub fn settings() -> server.Settings {
  server.Settings(
    pool: pool(),
    store: process.new_name("store"),
    hand_off: process.new_name("hand_off"),
    hand_off_shutdown_ms: 5000,
    login: login(),
  )
}

/// The database pool's configuration: PGHOST (an IPv6 address when it holds a
/// colon), PGPORT, PGUSER, PGPASSWORD and PGDATABASE, with Postgres's own
/// defaults for what is not set.
pub fn pool() -> pog.Config {
  let pool = pog.default_config(process.new_name("database_pool"))
  let pool = case envoy.get("PGHOST") {
    Ok(host) ->
      pool
      |> pog.host(host)
      |> pog.ip_version(case string.contains(host, ":") {
        True -> pog.Ipv6
        False -> pog.Ipv4
      })
    Error(Nil) -> pool
  }
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
  case envoy.get("PGPASSWORD") {
    Ok(password) -> pog.password(pool, Some(password))
    Error(Nil) -> pool
  }
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

/// The login's listeners from the environment: GENESIS_GAME_ADDRESS, the IPv4
/// address the client reaches the game server at, and GENESIS_REALM_NAME; the
/// ports are the client's defaults (6600, 23115, 24000), the realm id 1, each
/// key good for 60 s and each ask given 5 s. Recording is off and nothing is
/// planted; the dev start (dev/genesis_prime/dev_start) changes both.
fn login() -> server.Login {
  let address = case envoy.get("GENESIS_GAME_ADDRESS") {
    Ok(text) ->
      case ipv4_number(text) {
        Ok(address) -> address
        Error(Nil) ->
          panic as "GENESIS_GAME_ADDRESS is not an IPv4 address such as 127.0.0.1"
      }
    Error(Nil) ->
      panic as "GENESIS_GAME_ADDRESS is not set; the auth server hands each client to the game server at this IPv4 address"
  }
  let realm_name = case envoy.get("GENESIS_REALM_NAME") {
    Ok(name) -> name
    Error(Nil) ->
      panic as "GENESIS_REALM_NAME is not set; it names the realm the auth server hands each client to"
  }
  server.Login(
    sts_listener: "sts",
    sts_port: 6600,
    sts: sts_connection.Settings(
      ask_deadline_ms: 5000,
      game_token_lifetime_ms: 60_000,
    ),
    auth_listener: "auth",
    auth_port: 23_115,
    auth: auth_connection.Settings(
      realm: auth_connection.Realm(
        id: 1,
        name: realm_name,
        game_server: Endpoint(address:, port: 24_000),
      ),
      ask_deadline_ms: 5000,
      session_key_lifetime_ms: 60_000,
      planted: None,
    ),
    send_deadline_ms: 2000,
    connection_shutdown_ms: 5000,
    sts_recorder: None,
    auth_recorder: None,
  )
}

/// The 32-bit number of an IPv4 address written as four decimal numbers of
/// 0 to 255, so 127.0.0.1 is 0x7F000001.
fn ipv4_number(text: String) -> Result(Int, Nil) {
  case string.split(text, ".") {
    [first, second, third, fourth] -> {
      use first <- octet(first)
      use second <- octet(second)
      use third <- octet(third)
      use fourth <- octet(fourth)
      Ok(first * 16_777_216 + second * 65_536 + third * 256 + fourth)
    }
    _ -> Error(Nil)
  }
}

/// One decimal number of 0 to 255, of digits only.
fn octet(text: String, next: fn(Int) -> Result(Int, Nil)) -> Result(Int, Nil) {
  let digits_only =
    text != ""
    && list.all(string.to_graphemes(text), string.contains("0123456789", _))
  case digits_only, int.parse(text) {
    True, Ok(number) if number <= 255 -> next(number)
    _, _ -> Error(Nil)
  }
}
