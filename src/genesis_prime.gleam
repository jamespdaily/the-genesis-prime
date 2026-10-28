//// Starts the server: it loads the client's game tables from the folder named
//// by GENESIS_TABLE_DIR, stopping at once with the reason when one does not
//// load, then starts the supervision tree, with the database named by PGHOST,
//// PGPORT, PGUSER, PGPASSWORD and PGDATABASE, and keeps the node alive. It
//// serves the client's STS and auth logins (`login`) and the game server
//// (`game`).

import envoy
import genesis_prime/connection/registry
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import genesis_prime/step/runtime
import genesis_prime/table
import genesis_prime/table/loader/store
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist.{type Charlist}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pog

pub fn main() -> Nil {
  let #(tables, count) = load_tables()
  start(settings: settings(tables:), tables: count)
}

/// Loads the game tables from the folder GENESIS_TABLE_DIR names, once, into
/// their named records under the server's own key, which is the same in every
/// run (genesis_prime/table/loader/store); a missing variable or a table that
/// does not load stops the program with the reason. Gives the loaded tables, which the game
/// connections read, and how many there are.
pub fn load_tables() -> #(store.Tables, Int) {
  let folder = case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  case table.load_for_server(from: folder) {
    Ok(tables) -> #(tables, list.length(table.entries()))
    Error(error) -> panic as store.describe(error)
  }
}

/// Starts the supervision tree with these settings and keeps the node alive.
pub fn start(settings settings: server.Settings, tables tables: Int) -> Nil {
  runtime.show_info_lines()
  let assert Ok(_) = server.start(settings:)
    as "the supervision tree did not start"
  io.println(
    "the server loaded "
    <> int.to_string(tables)
    <> " game tables and serves the STS login on port "
    <> int.to_string(settings.login.sts.port)
    <> ", the auth login on port "
    <> int.to_string(settings.login.auth.port)
    <> " and the game server on port "
    <> int.to_string(settings.game.port),
  )
  process.sleep_forever()
}

/// The tree's settings: the database from the environment, with Postgres's
/// own defaults for what is not set, a fresh name for each child, and the
/// game tables the game connections read.
pub fn settings(tables tables: store.Tables) -> server.Settings {
  server.Settings(
    pool: pool(),
    store: process.new_name("store"),
    hand_off: process.new_name("hand_off"),
    hand_off_shutdown_ms: 5000,
    sessions: process.new_name("sessions"),
    sessions_shutdown_ms: 5000,
    registry: registry.new(),
    send_deadline_ms: 2000,
    connection_shutdown_ms: 5000,
    login: login(),
    game: game(tables),
  )
}

/// The database pool's configuration: PGHOST (an IPv6 address when it holds a
/// colon), PGPORT, PGUSER, PGPASSWORD and PGDATABASE, with Postgres's own
/// defaults for what is not set.
pub fn pool() -> pog.Config {
  let pool = pog.default_config(process.new_name("database_pool"))
  let pool =
    from_environment(pool, "PGHOST", fn(pool, host) {
      pool
      |> pog.host(host)
      |> pog.ip_version(case string.contains(host, ":") {
        True -> pog.Ipv6
        False -> pog.Ipv4
      })
    })
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
  from_environment(pool, "PGPASSWORD", fn(pool, password) {
    pog.password(pool, Some(password))
  })
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

/// The realm's id, the same in the auth server's hand-off and the game
/// server's hello and character list.
const realm_id = 1

/// The port the game server listens on and the auth server hands clients to:
/// the client's default.
const game_port = 24_000

/// The login's listeners from the environment: GENESIS_GAME_ADDRESS, the IPv4
/// address the client reaches the game server at, and GENESIS_REALM_NAME; the
/// ports are the client's defaults (6600, 23115), each key good for 60 s and
/// each ask given 5 s. Recording is off and nothing is planted; the dev start
/// (dev/genesis_prime/dev_start) changes both.
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
    sts: server.Served(
      listener: process.new_name("sts_listener"),
      port: 6600,
      settings: sts_connection.Settings(
        ask_deadline_ms: 5000,
        game_token_lifetime_ms: 60_000,
      ),
      recorder: None,
    ),
    auth: server.Served(
      listener: process.new_name("auth_listener"),
      port: 23_115,
      settings: auth_connection.Settings(
        realm: auth_connection.Realm(
          id: realm_id,
          name: realm_name,
          game_server: Endpoint(address:, port: game_port),
        ),
        ask_deadline_ms: 5000,
        session_key_lifetime_ms: 60_000,
        planted: None,
      ),
      recorder: None,
    ),
  )
}

/// The game server's listener: the client's default port, the realm the auth
/// server hands clients to, 12 characters in the list's field (the client's own
/// base slot count, BaseCharacterSlots in opcode.0x968; the client reads no
/// value of it), 2 character slots for an account (the count the client's
/// tables give an account with no entitlement,
/// lua.CharacterSelection.OnLoadFromCharacter), the game tables and each ask
/// given 5 s. Recording is off; the dev start changes it.
fn game(tables: store.Tables) -> server.Served(game_connection.Settings) {
  server.Served(
    listener: process.new_name("game_listener"),
    port: game_port,
    settings: game_connection.Settings(
      realm_id:,
      max_characters: 12,
      character_slots: 2,
      tables:,
      ask_deadline_ms: 5000,
    ),
    recorder: None,
  )
}

/// The 32-bit number of an IPv4 address written as four decimal numbers of
/// 0 to 255, so 127.0.0.1 is 0x7F000001.
fn ipv4_number(text: String) -> Result(Int, Nil) {
  parse_ipv4(charlist.from_string(text))
  |> result.map(fn(octets) {
    let #(first, second, third, fourth) = octets
    first * 16_777_216 + second * 65_536 + third * 256 + fourth
  })
  |> result.replace_error(Nil)
}

/// OTP's strict parse of four decimal numbers separated by dots.
@external(erlang, "inet", "parse_ipv4strict_address")
fn parse_ipv4(address: Charlist) -> Result(#(Int, Int, Int, Int), Atom)
