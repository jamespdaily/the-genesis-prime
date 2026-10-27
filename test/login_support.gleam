//// The login's two listeners for the tests that start the server's tree:
//// settings on ports the system picks and listener names made for each test,
//// so tests run side by side without sharing a port or a name, and the tree
//// itself, started on a database of the test's own with the account of the
//// library's vector inserted.

import ask_support
import database_support
import genesis_prime/add_account/sql
import genesis_prime/connection/listener
import genesis_prime/login/auth_connection
import genesis_prime/login/guid
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/server
import gleam/erlang/process.{type Pid}
import gleam/option.{None}
import login_client.{type Ports, Ports}
import login_rule_support as support
import login_vectors as vector
import pog
import pool_started

/// The realm the auth rule hands clients to.
pub fn realm() -> auth_connection.Realm {
  auth_connection.Realm(
    id: 1,
    name: "Nexus",
    game_server: Endpoint(address: 0x7F000001, port: 24_000),
  )
}

/// The settings of the STS rule.
pub fn sts_settings() -> sts_connection.Settings {
  sts_connection.Settings(ask_deadline_ms: 5000, game_token_lifetime_ms: 60_000)
}

/// The settings of the auth rule: nothing planted.
pub fn auth_settings() -> auth_connection.Settings {
  auth_connection.Settings(
    realm: realm(),
    ask_deadline_ms: 5000,
    session_key_lifetime_ms: 60_000,
    planted: None,
  )
}

/// The login's listeners on ports the system picks, with names made now, no
/// recording and nothing planted.
pub fn login() -> server.Login {
  server.Login(
    sts: server.Served(
      listener: process.new_name("test_sts_listener"),
      port: 0,
      settings: sts_settings(),
      recorder: None,
    ),
    auth: server.Served(
      listener: process.new_name("test_auth_listener"),
      port: 0,
      settings: auth_settings(),
      recorder: None,
    ),
    send_deadline_ms: 300,
    connection_shutdown_ms: 1000,
  )
}

/// A running tree: its supervisor and the settings it was started with.
pub type Started {
  Started(tree: Pid, settings: server.Settings)
}

/// Starts the server's tree on a database of its own and waits for its pool.
pub fn start() -> Started {
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let settings =
    server.Settings(
      pool: database_support.config(
        for: shared.settings,
        database:,
        pool_name: process.new_name("pool"),
        pool_size: 2,
      ),
      store: process.new_name("store"),
      hand_off: process.new_name("hand_off"),
      hand_off_shutdown_ms: 1500,
      login: login(),
    )
  let assert Ok(started) = server.start(settings) as "the tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  assert pool_started.await(settings.pool.pool_name, within_ms: 30_000)
    as "the pool opened its connections"
  Started(tree: started.pid, settings:)
}

/// The ports the tree's two listeners opened.
pub fn ports(started: Started) -> Ports {
  let login = started.settings.login
  let assert Ok(sts_port) = listener.port(login.sts.listener)
    as "the STS listener has a port"
  let assert Ok(auth_port) = listener.port(login.auth.listener)
    as "the auth listener has a port"
  Ports(sts_port:, auth_port:)
}

/// Inserts an account into the tree's database, as the add-account tool does,
/// and gives its id.
pub fn insert_account(
  pool pool: pog.Connection,
  login_name login_name: String,
  salt salt: BitArray,
  verifier verifier: BitArray,
  game_account_id game_account_id: guid.Guid,
) -> Int {
  let assert Ok(pog.Returned(rows: [sql.InsertAccountRow(account_id:)], ..)) =
    sql.insert_account(
      pool,
      login_name,
      salt,
      verifier,
      guid.to_text(game_account_id),
    )
    as "the account was inserted"
  account_id
}

/// Inserts the account of the library's vector, `jim`, and gives its id.
pub fn insert_jim(started: Started) -> Int {
  insert_account(
    pool: pog.named_connection(started.settings.pool.pool_name),
    login_name: vector.name,
    salt: vector.salt(),
    verifier: vector.verifier(),
    game_account_id: support.jim().game_account_id,
  )
}
