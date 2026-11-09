//// What the tests of the content tables share: a connection to a database of the
//// test's own, and the fixture of the world database.

import character_tables
import database_support
import event_wait
import genesis_prime
import genesis_prime/content
import genesis_prime/readiness
import genesis_prime/table/loader/store as table_store
import gleam/erlang/process
import gleam/int
import gleam/result
import gleam/string
import owned_key
import pog

/// The folder that holds the planted file of the world database
/// (`test/fixture/world_data/spawn.tsv`): the header and the 27 rows of the
/// Virtual Battle Beasts, 29113 to 29139.
pub const fixture_folder = "test/fixture/world_data"

/// A one-connection pool on the database, ready for its first query: a pool
/// opens its connection after it starts, so a first query is asked again while
/// none is open.
pub fn connect(database database: String) -> pog.Connection {
  connect_with(config: database_support.config(
    database_support.settings(),
    database:,
    pool_name: process.new_name("content_test_pool"),
    pool_size: 1,
  ))
}

/// A pool of this configuration, ready for its first query.
pub fn connect_with(config config: pog.Config) -> pog.Connection {
  let assert Ok(started) = pog.start(config) as "the pool started"
  event_wait.until("the pool has a connection", fn() {
    result.is_ok(pog.query("select 1") |> pog.execute(started.data))
  })
  started.data
}

/// The result of one query of the test's own on the database, as text rows of
/// `psql -At`, trimmed.
pub fn psql(database database: String, sql sql: String) -> String {
  let assert Ok(output) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: ["-At", "-c", sql],
    )
    as "the query ran"
  string.trim(output)
}

/// The count a `select count(*)` gives.
pub fn count(database database: String, sql sql: String) -> Int {
  let assert Ok(number) = int.parse(psql(database:, sql:))
    as "the query gave a number"
  number
}

/// How the load asks in these tests: attempts of 500 ms, 50 ms between them, and
/// the warning after a second.
pub fn asking() -> readiness.Settings {
  readiness.Settings(within_ms: 1000, attempt_ms: 500, pause_ms: 50)
}

/// The load of the committed content tables and the repository's migrations from the
/// database, under a key of its own.
pub fn load(
  database database: String,
) -> #(Result(Nil, content.LoadError), table_store.Key) {
  load_asking(database:, ask: asking(), probe: content.pool_probe)
}

/// The load with the way it asks the pool chosen by the test.
pub fn load_asking(
  database database: String,
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
) -> #(Result(Nil, content.LoadError), table_store.Key) {
  let key = owned_key.new_fixture_key()
  let pool =
    database_support.config(
      database_support.settings(),
      database:,
      pool_name: process.new_name("content_load_pool"),
      pool_size: 1,
    )
  #(
    content.load(
      tables: character_tables.content_tables(),
      migrations: genesis_prime.load_migrations(),
      pool:,
      ask:,
      probe:,
      key:,
    ),
    key,
  )
}

/// Runs `sql` on the database as the test's administrator.
pub fn change(database database: String, sql sql: String) -> Nil {
  let assert Ok(_) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: ["-c", sql],
    )
    as "the change to the database ran"
  Nil
}
