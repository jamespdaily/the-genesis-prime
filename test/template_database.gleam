//// Database isolation by template copy: each test gets its own database made
//// from the run's migrated template, and the database is dropped afterwards.
//// A guardian process the test does not own makes the database and drops it
//// when the test returns, crashes, is killed or runs past its deadline. Code
//// under test, including code that opens its own transaction, and processes
//// the test starts run against the database as they do against the server's.

import database_support.{type Settings}
import genesis_prime/database/pool
import genesis_prime/server
import genesis_prime/shutdown
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/erlang/reference
import gleam/int
import gleam/otp/actor
import gleam/result
import pog

/// A database that belongs to one test.
pub type Database {
  Database(name: String, connection: pog.Connection, settings: Settings)
}

/// Why the guardian could not hand the test a database.
pub type Failure {
  NotCreated(pog.QueryError)
  PoolNotStarted(actor.StartError)
}

/// What the guardian tells the test: the database, or why there is none.
type Started =
  Result(Database, Failure)

/// Runs `body` with a fresh database copied from the run's template, which
/// holds every migration in `priv/migrations`. Call it inside `owned_test.run`.
pub fn run(body: fn(Database) -> a) -> a {
  let shared = database_support.shared()
  let started = process.new_subject()
  let owner = process.self()
  process.spawn_unlinked(fn() { guard(for: shared, owner:, started:) })
  let database = case process.receive(started, 60_000) {
    Ok(Ok(database)) -> database
    Ok(Error(NotCreated(_))) -> panic as "the database was not created"
    Ok(Error(PoolNotStarted(_))) -> panic as "the database's pool did not start"
    Error(Nil) -> panic as "the database was not made within 60 seconds"
  }
  body(database)
}

/// The configuration of a pool of `pool_size` connections to the test's own
/// database, for a process the test starts.
pub fn config(
  for database: Database,
  pool_name pool_name: Name(pog.Message),
  pool_size pool_size: Int,
) -> pog.Config {
  database_support.config(
    for: database.settings,
    database: database.name,
    pool_name:,
    pool_size:,
  )
}

/// The settings of a pool of `pool_size` connections to the test's own
/// database, for a tree the test starts with `server.start`.
pub fn pool_settings(
  for database: Database,
  pool_name pool_name: Name(pog.Message),
  pool_size pool_size: Int,
) -> pool.Settings {
  pool.Settings(
    name: pool_name,
    host: database.settings.tcp_host,
    port: database.settings.port,
    database: database.name,
    user: database.settings.user,
    password: database.settings.password,
    pool_size:,
  )
}

/// The settings of the whole tree around a pool, for a test that starts it with
/// `server.start`: no game table is read, and the shutdown has deadlines of 1
/// second, which a test that does not stop the server never meets.
pub fn tree_settings(pool_settings: pool.Settings) -> server.Settings {
  server.Settings(
    pool: pool_settings,
    tables: server.TableSettings(
      key: reference.new(),
      folder: "",
      entries: [],
      requirements: [],
    ),
    shutdown: shutdown.new(drain_deadline_ms: 1000, flush_deadline_ms: 1000),
  )
}

/// Makes the database, hands it to `owner`, then waits for `owner` to die and
/// drops the database. The owner dies after its body returns, crashes, is
/// killed or runs past its deadline, and everything the owner linked to is
/// stopping by then, so no process of the test holds a connection to the
/// database when it is dropped; whatever still does is disconnected by the drop.
fn guard(
  for shared: database_support.Shared,
  owner owner: Pid,
  started started: Subject(Started),
) -> Nil {
  let monitor = process.monitor(owner)
  case create(shared) {
    Error(failure) -> process.send(started, Error(failure))
    Ok(#(database, pool)) -> {
      process.send(started, Ok(database))
      wait_until_dead(monitor)
      database_support.stop_pool(pool)
      drop(shared, database)
    }
  }
}

fn create(
  shared: database_support.Shared,
) -> Result(#(Database, Pid), Failure) {
  let name = shared.run <> "_" <> int.to_string(database_support.unique())
  use _ <- result.try(
    database_support.execute(
      on: shared,
      sql: "create database \""
        <> name
        <> "\" template \""
        <> shared.template
        <> "\"",
    )
    |> result.map_error(NotCreated),
  )
  let pool_name = process.new_name("template_database")
  let config =
    database_support.config(
      for: shared.settings,
      database: name,
      pool_name:,
      pool_size: 2,
    )
  use pool <- result.map(pog.start(config) |> result.map_error(PoolNotStarted))
  #(Database(name:, connection: pool.data, settings: shared.settings), pool.pid)
}

fn drop(shared: database_support.Shared, database: Database) -> Nil {
  let assert Ok(Nil) =
    database_support.execute(
      on: shared,
      sql: "drop database \"" <> database.name <> "\" with (force)",
    )
    as "the test's database was not dropped"
  Nil
}

fn wait_until_dead(owner: Monitor) -> Nil {
  process.new_selector()
  |> process.select_specific_monitor(owner, fn(_down) { Nil })
  |> process.selector_receive_forever
}
