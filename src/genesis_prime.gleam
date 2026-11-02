//// Starts the server: it loads the client's game tables from the folder named
//// by GENESIS_TABLE_DIR, stopping at once with the reason when one does not
//// load, then starts the supervision tree under the application's root
//// (genesis_prime/application), with the database named by PGHOST, PGPORT,
//// PGUSER, PGPASSWORD and PGDATABASE. Once one read of the database has
//// returned, and the migrations the database recorded are the files in
//// priv/migrations (genesis_prime/migration), it prints the ready line, and it
//// keeps the node alive until SIGTERM, which OTP turns into the tree's ordered
//// stop and then the node's. A database that lacks a migration, ran a
//// migration this build has no file for, ran an edited one, has no record of
//// its migrations or cannot be read makes `main` stop with the reason and the
//// node end with status 1, with no ready line, however late the database
//// answers: one that is down at start is logged as unreachable and asked again
//// until it answers.
//// It serves the client's STS and auth logins (`login`) and the game server
//// (`game`).

import envoy
import genesis_prime/application
import genesis_prime/client_connection.{type Bucket}
import genesis_prime/connection/registry
import genesis_prime/digest
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/migration
import genesis_prime/readiness
import genesis_prime/server
import genesis_prime/step
import genesis_prime/step/runtime
import genesis_prime/store/worker
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import gleam/erlang/application as erlang_application
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
import simplifile

pub fn main() -> Nil {
  let #(tables, count) = load_tables()
  start(settings: settings(tables:), tables: count)
}

/// Loads the game tables the server's rules read
/// (genesis_prime/table/loader/server_table) from the folder GENESIS_TABLE_DIR
/// names, once, into their named records under the server's own key, which is
/// the same in every run (genesis_prime/table/loader/store); a missing
/// variable or a table that does not load stops the program with the reason.
/// Gives the loaded tables, which the game connections read, and how many
/// tables there are.
pub fn load_tables() -> #(store.Tables, Int) {
  let folder = case envoy.get("GENESIS_TABLE_DIR") {
    Ok(folder) -> folder
    Error(Nil) ->
      panic as "GENESIS_TABLE_DIR is not set; the server loads the client's game tables from the folder it names"
  }
  case server_table.load(from: folder) {
    Ok(tables) -> #(tables, list.length(server_table.entries()))
    Error(error) -> panic as store.describe(error)
  }
}

/// Reads the migration files of the application's priv/migrations once, each
/// as its name without `.sql` and the SHA-256 of its bytes, in name order,
/// which the readiness ask compares with what the database recorded. A folder
/// or a file that cannot be read stops the program with the reason.
pub fn load_migrations() -> List(migration.Migration) {
  let assert Ok(priv) = erlang_application.priv_directory("genesis_prime")
    as "the application's priv folder was not found"
  let folder = priv <> "/migrations"
  let assert Ok(names) = simplifile.read_directory(folder)
    as { "the migration folder " <> folder <> " could not be read" }
  names
  |> list.filter(string.ends_with(_, ".sql"))
  |> list.sort(string.compare)
  |> list.map(fn(file) {
    let assert Ok(bytes) = simplifile.read_bits(folder <> "/" <> file)
      as { "the migration file " <> file <> " could not be read" }
    migration.Migration(
      name: string.remove_suffix(file, ".sql"),
      sha256: digest.sha256(bytes),
    )
  })
}

/// Starts the supervision tree with these settings under the application's
/// root (genesis_prime/application), says whether the server can serve, and
/// keeps the node alive until the tree ends, which the host's SIGTERM makes
/// through OTP. It reads the migration files once, before the tree starts.
pub fn start(settings settings: server.Settings, tables tables: Int) -> Nil {
  runtime.show_info_lines()
  runtime.keep_mailboxes_out_of_crash_reports()
  let migrations = load_migrations()
  let assert Ok(tree) = application.start_server(settings:)
    as "the supervision tree did not start"
  serve(
    tree:,
    settings:,
    tables:,
    ready: ready_ask(),
    probe: fn(reply) { worker.probe(store: settings.store, reply:) },
    migrations:,
    say: io.println,
  )
}

/// Asks the database through `probe` until it answers, says through `say` what
/// the server can do, and keeps the node alive until the tree ends. The ready
/// line is said only when the database answered, the migrations it recorded
/// are `migrations`, and the server still serves: its tree is running and the
/// node is not stopping. A stop can begin between that check and the line
/// being said. A database that does not answer within the ask's time is logged
/// once as a warning, and the server keeps running and keeps asking, with the
/// same attempts and pauses, until the database answers or the node is
/// stopping, so a database that comes up late is checked too, and the ready
/// line is said then. A database whose migrations differ from `migrations`,
/// whenever it answers, stops `main` with the difference
/// (`migration.describe`), which ends the node with status 1; a tree that ends
/// is taken as `application.end_of` takes it. `start` calls it with the
/// server's own ask, the files it read and `io.println`; the tests call it with
/// their own.
pub fn serve(
  tree tree: application.Tree,
  settings settings: server.Settings,
  tables tables: Int,
  ready ready: readiness.Settings,
  probe probe: readiness.Probe,
  migrations migrations: List(migration.Migration),
  say say: fn(String) -> Nil,
) -> Nil {
  let outcome =
    readiness.await(
      probe:,
      tree: tree.monitor,
      settings: ready,
      files: migrations,
    )
  case outcome {
    readiness.DatabaseUnreachable ->
      runtime.log(step.LogWarning, "the database is unreachable", step.no_one)
    readiness.Ready
    | readiness.MigrationsRefused(..)
    | readiness.TreeEnded(..) -> Nil
  }
  settle(outcome:, tree:, settings:, tables:, ready:, probe:, migrations:, say:)
}

/// Acts on what the readiness ask found: says the ready line, stops `main` for
/// a refusal, takes the tree's end, or, when the database has not answered,
/// asks again unless the node is stopping.
fn settle(
  outcome outcome: readiness.Outcome,
  tree tree: application.Tree,
  settings settings: server.Settings,
  tables tables: Int,
  ready ready: readiness.Settings,
  probe probe: readiness.Probe,
  migrations migrations: List(migration.Migration),
  say say: fn(String) -> Nil,
) -> Nil {
  case outcome {
    readiness.Ready -> {
      case application.serving(tree) {
        True -> say(ready_line(settings:, tables:))
        False -> Nil
      }
      application.await_tree_end(tree)
    }
    readiness.MigrationsRefused(refusal:) -> panic as migration.describe(refusal)
    readiness.DatabaseUnreachable ->
      case application.node_stopping() {
        True -> application.await_tree_end(tree)
        False ->
          settle(
            outcome: readiness.await(
              probe:,
              tree: tree.monitor,
              settings: ready,
              files: migrations,
            ),
            tree:,
            settings:,
            tables:,
            ready:,
            probe:,
            migrations:,
            say:,
          )
      }
    readiness.TreeEnded(reason:) -> application.end_of(reason)
  }
}

/// How the readiness ask runs. These are the server's choice, not the
/// client's: 30 s in all, so a database that is still starting when the server
/// does has time to accept connections; each attempt waits 2 s, the length of a
/// write's send deadline, before its worker is ended; a failed attempt is asked
/// again after 250 ms, so a pool that opens its connections in a few hundred
/// milliseconds is found at once. A database that has not answered in that time
/// is asked again in windows of the same length.
fn ready_ask() -> readiness.Settings {
  readiness.Settings(within_ms: 30_000, attempt_ms: 2000, pause_ms: 250)
}

/// The ready line, the one the live-play scripts wait for.
fn ready_line(
  settings settings: server.Settings,
  tables tables: Int,
) -> String {
  "the server loaded "
  <> int.to_string(tables)
  <> " game tables and serves the STS login on port "
  <> int.to_string(settings.login.sts.port)
  <> ", the auth login on port "
  <> int.to_string(settings.login.auth.port)
  <> " and the game server on port "
  <> int.to_string(settings.game.port)
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
    sessions_recorder: None,
    registry: registry.new(),
    world: world(),
    send_deadline_ms: 2000,
    connection_shutdown_ms: 5000,
    login: login(),
    game: game(tables),
  )
}

/// The world subtree's names, and its times: a watch's call to Maps may take
/// 5 s, the same as an ask, and a map has 5 s to stop. Recording is off; the
/// dev start changes it.
fn world() -> server.World {
  server.World(
    maps: process.new_name("maps"),
    map_supervisor: process.new_name("map_supervisor"),
    maps_call_ms: 5000,
    map_shutdown_ms: 5000,
    map_recordings: None,
  )
}

/// The database pool's three sizes. The values are the server's choice, not
/// the client's, and are pog's own defaults: the load run's two runs of
/// 2026-11-01 (see `game_max_connections`) never had a store worker waiting
/// for the pool, so no measurement asks for others.
pub type PoolSettings {
  PoolSettings(
    /// How many connections the pool keeps open: pog's default, 10.
    pool_size: Int,
    /// How long, in milliseconds, a checkout may wait in the queue before the
    /// queue counts as slow: pog's default, 50.
    queue_target: Int,
    /// How long, in milliseconds, checkouts must stay slower than
    /// `queue_target` before the pool doubles it and starts dropping checkouts
    /// past it: pog's default, 1000.
    queue_interval: Int,
  )
}

/// The server's pool sizes.
pub const pool_settings =
  PoolSettings(pool_size: 10, queue_target: 50, queue_interval: 1000)

/// The database pool's configuration with the server's pool sizes
/// (`pool_settings`): PGHOST (an IPv6 address when it holds a colon), PGPORT,
/// PGUSER, PGPASSWORD and PGDATABASE, with Postgres's own defaults for what is
/// not set.
pub fn pool() -> pog.Config {
  pool_with(sizes: pool_settings)
}

/// The database pool's configuration with these pool sizes, and the
/// connection's settings from the environment as `pool` reads them.
pub fn pool_with(sizes sizes: PoolSettings) -> pog.Config {
  let pool =
    pog.default_config(process.new_name("database_pool"))
    |> pog.pool_size(sizes.pool_size)
    |> pog.queue_target(sizes.queue_target)
    |> pog.queue_interval(sizes.queue_interval)
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

/// How long an ask to the store, the hand-off, Sessions or a map may take, in
/// every rule.
const ask_deadline_ms = 5000

/// How many connections each listener holds at once is the server's choice: half
/// of 4,800, the most players a step of the load run (`genesis_prime/load_run`)
/// kept up with, in two runs on 2026-11-01 on an Apple M2 Max (12 cores, 32 GB,
/// macOS 26.7.1) that also ran the clients on four of its schedulers, with
/// Postgres 18.6 and the pool below. Each player held one connection on each
/// listener, so each listener's cap is a connection for each of 2,400 players.
/// Nothing on the server failed a line up to 4,800 players (login to world 6 ms
/// at the 99th percentile, ping 5 ms, at most 7% of the cores, no mailbox that
/// never emptied, no store worker waiting); the run's next step, 6,400, was
/// the clients' limit, since this machine ran out of local ports at about 5,400
/// players, so 4,800 is a floor of what the server takes. The rate below
/// stays at the client's own.
const sts_max_connections = 2400

const auth_max_connections = 2400

const game_max_connections = 2400

/// A rule's rate placeholders. The recording of the live session's game
/// connection (102 frames, counted by the read that completed each) holds 15
/// frames in one read, 19 within 29 ms of each other, and at most 20 in any
/// second, so `per_second` is 20 for the game and the logins send a handful of
/// requests in all, so 4. A rule counts the frames that wait for an ask only
/// when the ask is answered, so `burst` holds what a client sends at its rate
/// through the rule's longest wait (`client_connection.bucket` refuses less):
/// - STS: one ask, 5 s, so 4 * 5 = 20.
/// - auth: two asks in a row, 10 s, so 4 * 10 = 40.
/// - game: two asks in a row and the claim's retries, 2 * 5 s + 5 * 100 ms =
///   10.5 s, so 20 * 10.5 = 210.
fn sts_rate() -> Bucket {
  rate(
    burst: 20,
    per_second: 4,
    longest_wait_ms: sts_connection.longest_wait_ms(ask_deadline_ms:),
  )
}

fn auth_rate() -> Bucket {
  rate(
    burst: 40,
    per_second: 4,
    longest_wait_ms: auth_connection.longest_wait_ms(ask_deadline_ms:),
  )
}

fn game_rate() -> Bucket {
  rate(
    burst: 210,
    per_second: 20,
    longest_wait_ms: game_connection.longest_wait_ms(ask_deadline_ms:),
  )
}

/// A rate bucket, or a stop with the reason when the values are refused.
fn rate(
  burst burst: Int,
  per_second per_second: Int,
  longest_wait_ms longest_wait_ms: Int,
) -> Bucket {
  case client_connection.bucket(burst:, per_second:, longest_wait_ms:) {
    Ok(bucket) -> bucket
    Error(refused) -> panic as client_connection.describe_refusal(refused)
  }
}

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
      max_connections: sts_max_connections,
      settings: sts_connection.Settings(
        ask_deadline_ms:,
        game_token_lifetime_ms: 60_000,
        rate: sts_rate(),
      ),
      recorder: None,
    ),
    auth: server.Served(
      listener: process.new_name("auth_listener"),
      port: 23_115,
      max_connections: auth_max_connections,
      settings: auth_connection.Settings(
        realm: auth_connection.Realm(
          id: realm_id,
          name: realm_name,
          game_server: Endpoint(address:, port: game_port),
        ),
        ask_deadline_ms:,
        session_key_lifetime_ms: 60_000,
        planted: None,
        rate: auth_rate(),
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
    max_connections: game_max_connections,
    settings: game_connection.Settings(
      realm_id:,
      max_characters: 12,
      character_slots: 2,
      tables:,
      ask_deadline_ms:,
      rate: game_rate(),
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
