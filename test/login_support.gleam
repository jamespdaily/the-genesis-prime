//// The listeners for the tests that start the server's tree:
//// settings on ports the system picks and listener names made for each test,
//// so tests run side by side without sharing a port or a name, and the tree
//// itself, started on a database of the test's own with the account of the
//// library's vector inserted.

import ask_support
import character_tables
import connection_rule_support as support
import database_support
import driven_time
import envoy
import event_wait
import fixed_seed
import game_connection_support
import genesis_prime
import genesis_prime/add_account/sql
import genesis_prime/client_connection.{type Bucket, type Request}
import genesis_prime/connection/listener
import genesis_prime/connection/registry
import genesis_prime/connection/script.{type Scripts}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/login/auth_connection
import genesis_prime/login/guid
import genesis_prime/login/sts_connection
import genesis_prime/server
import genesis_prime/service/shell.{type ServiceTime}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/wire_recording/recorder.{type WireRecorder}
import genesis_prime/world_map/creature_registry
import gleam/erlang/process.{type Pid}
import gleam/option.{None, Some}
import login_client.{type Ports, Ports}
import login_settings_support
import login_vectors as vector
import pog
import readiness_support
import spawn_support

/// The most connections each test listener holds, a different number for each
/// so a listener given another's setting shows.
pub const sts_max_connections = 50

pub const auth_max_connections = 51

pub const game_max_connections = 52

/// The login's listeners on ports the system picks, with names made now, no
/// recording, nothing planted, and connections that take `scripts`.
fn login(scripts: Scripts) -> server.Login {
  server.Login(
    sts: server.Served(
      listener: process.new_name("test_sts_listener"),
      port: 0,
      max_connections: sts_max_connections,
      settings: login_settings_support.sts_settings(),
      wire_recorder: None,
      scripts:,
    ),
    auth: server.Served(
      listener: process.new_name("test_auth_listener"),
      port: 0,
      max_connections: auth_max_connections,
      settings: login_settings_support.auth_settings(),
      wire_recorder: None,
      scripts:,
    ),
  )
}

/// The world subtree with names made now and no recording.
fn world() -> server.World {
  server.World(
    maps: process.new_name("test_maps"),
    map_supervisor: process.new_name("test_map_supervisor"),
    maps_call_ms: ask_support.beyond_the_test_ms,
    map_shutdown_ms: 1000,
    creatures: creature_registry.new(),
    creature_supervisor: process.new_name("test_creature_supervisor"),
    creature_shutdown_ms: 1000,
    idle_stop_ms: 60_000,
    sweep_ms: 10_000,
    spawns: spawn_support.key_without_spawns(),
  )
}

/// The game server's listener on a port the system picks, with a name made now,
/// no recording and connections that take `scripts`.
fn game(scripts: Scripts) -> server.Served(game_connection.Settings) {
  server.Served(
    listener: process.new_name("test_game_listener"),
    port: 0,
    max_connections: game_max_connections,
    settings: login_settings_support.game_settings(),
    wire_recorder: None,
    scripts:,
  )
}

/// A running tree: its supervisor and the settings it was started with.
pub type Started {
  Started(tree: Pid, settings: server.Settings)
}

/// The server's settings for a test on the driven clock `time`: the pool given,
/// names made now, the listeners on ports the system picks, nothing recorded,
/// and every clock of the tree read from `time`: the STS, auth and game
/// connections, the hand-off, Sessions, the maps and the creatures take the time
/// of each input and start their timers there, so a timer fires only when the
/// test advances `time`. The deadlines the server counts on the node's own time
/// are far beyond the test's own deadline (`with_deadlines_beyond_the_tests`).
pub fn settings(
  pool pool: pog.Config,
  time time: driven_time.Time,
) -> server.Settings {
  settings_over(
    pool:,
    scripts: driven_time.connection_scripts(time),
    service_time: driven_time.service_time(time),
  )
}

/// The server's settings as `settings` makes them over the connections' `scripts`
/// and the services' `service_time`, which a test that runs a node of its own
/// gives its own.
pub fn settings_over(
  pool pool: pog.Config,
  scripts scripts: Scripts,
  service_time service_time: ServiceTime,
) -> server.Settings {
  with_deadlines_beyond_the_tests(
    fixed_seed.seeded(server.Settings(
      pool:,
      store: process.new_name("store"),
      hand_off: process.new_name("hand_off"),
      tree_restarts: server.Restarts(intensity: 3, period_s: 10),
      hand_off_shutdown_ms: 1500,
      sessions: process.new_name("sessions"),
      sessions_shutdown_ms: 1500,
      registry: registry.new(),
      service_time:,
      world: world(),
      send_deadline_ms: ask_support.beyond_the_test_ms,
      connection_shutdown_ms: 2 * ask_support.beyond_the_test_ms,
      login: login(scripts),
      game: game(scripts),
    )),
  )
}

/// The settings with every deadline the server counts on the node's own time far
/// beyond the test's own deadline (`ask_support.beyond_the_test_ms`), so none
/// passes while a test runs, and the test's deadline warns of a wait that is never
/// answered: a write's, a call to Maps, each connection's ask and the connections'
/// stop. A stop leaves a connection's save the shutdown time less the send
/// deadline (`connection/shell` `stop_deadline`), and a save with no time left is
/// given up with a warning (`game/connection/state` `end_with`), so the shutdown
/// time is twice that distance and a stop's save is bounded by the ask deadline
/// only.
pub fn with_deadlines_beyond_the_tests(
  settings: server.Settings,
) -> server.Settings {
  let beyond = ask_support.beyond_the_test_ms
  server.Settings(
    ..settings,
    send_deadline_ms: beyond,
    connection_shutdown_ms: 2 * beyond,
    world: server.World(..settings.world, maps_call_ms: beyond),
    login: server.Login(
      sts: server.Served(
        ..settings.login.sts,
        settings: sts_connection.Settings(
          ..settings.login.sts.settings,
          ask_deadline_ms: beyond,
        ),
      ),
      auth: server.Served(
        ..settings.login.auth,
        settings: auth_connection.Settings(
          ..settings.login.auth.settings,
          ask_deadline_ms: beyond,
        ),
      ),
    ),
    game: server.Served(
      ..settings.game,
      settings: connection_state.Settings(
        ..settings.game.settings,
        ask_deadline_ms: beyond,
      ),
    ),
  )
}

/// The settings with every clock of the tree read from `time`
/// (`driven_time.scripts`, `driven_time.service_time`): the connections' scripts
/// are the settings' own with the driven clock and timers in place of theirs (their
/// seeds stay), and the services take `time`.
pub fn on_the_clock(
  settings settings: server.Settings,
  time time: driven_time.Time,
) -> server.Settings {
  let login = settings.login
  server.Settings(
    ..settings,
    service_time: driven_time.service_time(time),
    login: server.Login(
      sts: server.Served(
        ..login.sts,
        scripts: driven_time.scripts(time:, over: login.sts.scripts),
      ),
      auth: server.Served(
        ..login.auth,
        scripts: driven_time.scripts(time:, over: login.auth.scripts),
      ),
    ),
    game: server.Served(
      ..settings.game,
      scripts: driven_time.scripts(time:, over: settings.game.scripts),
    ),
  )
}

/// The settings the server's own start makes, on the driven clock `time`, with
/// every deadline beyond the test (`on_the_clock`, `with_deadlines_beyond_the_tests`): for a test
/// that replays a recording against the server's own rules.
pub fn servers_settings_on(time time: driven_time.Time) -> server.Settings {
  with_deadlines_beyond_the_tests(on_the_clock(
    settings: servers_settings(),
    time:,
  ))
}

/// The settings the server's own start makes, over the content terms the test
/// helpers put by hand (`spawn_support.key_without_spawns`). They read two
/// variables that a started server sets for real; this gives them values.
pub fn servers_settings() -> server.Settings {
  servers_settings_over(spawns: spawn_support.key_without_spawns())
}

/// The settings the server's own start makes, over the content terms under `spawns`
/// (a key a content load wrote, or one a helper filled).
pub fn servers_settings_over(spawns spawns: Key) -> server.Settings {
  envoy.set("GENESIS_GAME_ADDRESS", "127.0.0.1")
  envoy.set("GENESIS_REALM_NAME", "Test")
  fixed_seed.seeded(genesis_prime.settings(
    tables: character_tables.shared(),
    spawns:,
  ))
}

/// The rate bucket the server's own settings give the auth rule.
pub fn servers_auth_rate() -> Bucket {
  servers_settings().login.auth.settings.rate
}

/// Starts the server's tree as `start` does, with the auth listener's rate as
/// `rate` and its connections recorded on the wire by `recorder`.
pub fn start_recording_auth(
  rate rate: Bucket,
  recorder recorder: WireRecorder,
  time time: driven_time.Time,
) -> Started {
  start_with(time:, change: fn(settings) {
    let auth = settings.login.auth
    server.Settings(
      ..settings,
      login: server.Login(
        ..settings.login,
        auth: server.Served(
          ..auth,
          settings: auth_connection.Settings(..auth.settings, rate:),
          wire_recorder: Some(recorder),
        ),
      ),
    )
  })
}

/// Starts the server's tree on the driven clock `time`, on a database of its
/// own, and waits for its pool.
pub fn start(time time: driven_time.Time) -> Started {
  start_with(time:, change: fn(settings) { settings })
}

/// Starts the server's tree as `start` does, with the settings as `change`
/// makes them.
pub fn start_with(
  time time: driven_time.Time,
  change change: fn(server.Settings) -> server.Settings,
) -> Started {
  let shared = database_support.shared()
  start_on(
    time:,
    shared:,
    database: database_support.new_database(on: shared),
    change:,
  )
}

/// Starts the server's tree as `start_with` does, on the database `database`
/// of the test's own, which the test has made and may have filled first.
pub fn start_on(
  time time: driven_time.Time,
  shared shared: database_support.Shared,
  database database: String,
  change change: fn(server.Settings) -> server.Settings,
) -> Started {
  started_from(shared:, database:, settings: fn(pool) {
    change(settings(pool:, time:))
  })
}

/// Starts the tree with the settings `make` gives over the pool of `database`,
/// and waits until its database answers.
fn started_from(
  shared shared: database_support.Shared,
  database database: String,
  settings make: fn(pog.Config) -> server.Settings,
) -> Started {
  let settings =
    make(database_support.config(
      for: shared.settings,
      database:,
      pool_name: process.new_name("pool"),
      pool_size: 2,
    ))
  let assert Ok(started) = server.start(settings) as "the tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  readiness_support.await(tree: started.pid, store: settings.store)
  Started(tree: started.pid, settings:)
}

/// The ports the tree's three listeners opened.
pub fn ports(started: Started) -> Ports {
  let login = started.settings.login
  let assert Ok(sts_port) = listener.port(login.sts.listener)
    as "the STS listener has a port"
  let assert Ok(auth_port) = listener.port(login.auth.listener)
    as "the auth listener has a port"
  let assert Ok(game_port) = listener.port(started.settings.game.listener)
    as "the game listener has a port"
  Ports(sts_port:, auth_port:, game_port:)
}

/// Starts the tree and inserts the account of the library's vector: the tree,
/// its ports and the account's id.
pub fn start_with_jim(time time: driven_time.Time) -> #(Started, Ports, Int) {
  let started = start(time:)
  let account_id = insert_jim(started)
  #(started, ports(started), account_id)
}

/// Stops the tree and waits for it to end.
pub fn stop(started: Started) -> Nil {
  let _reason = ask_support.stop_tree(started.tree)
  Nil
}

/// Waits until the game listener holds no connection, which is when the
/// connection that ended has saved and stopped.
pub fn await_no_game_connection(started: Started) -> Nil {
  event_wait.until("the game listener's connection ended", fn() {
    ask_support.connections_of(started.settings.game.listener) == []
  })
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
  insert_other(
    started:,
    login_name: vector.name,
    game_account_id: support.jim().game_account_id,
  )
}

/// Inserts another account with the library's vector's password, as the login
/// name `login_name` and the game account `game_account_id`, and gives its id:
/// for a test with two players, which logs neither in through the login
/// servers.
pub fn insert_other(
  started started: Started,
  login_name login_name: String,
  game_account_id game_account_id: guid.Guid,
) -> Int {
  insert_account(
    pool: pog.named_connection(started.settings.pool.pool_name),
    login_name:,
    salt: vector.salt(),
    verifier: vector.verifier(),
    game_account_id:,
  )
}

/// The connection after 0x058F, with its ask to take the session key.
pub fn replied() -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    game_connection_support.connected(),
    game_connection_support.hello_reply(),
  )
}
