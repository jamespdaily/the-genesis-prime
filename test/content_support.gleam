//// What the tests of the content tables share: a connection to a database of the
//// test's own, and the fixture of the world database.

import ask_support
import character_tables
import database_support
import event_wait
import genesis_prime
import genesis_prime/content
import genesis_prime/content/objective_set
import genesis_prime/content/spawn as content_spawn
import genesis_prime/content/terrain as content_terrain
import genesis_prime/dev_database
import genesis_prime/game/arrival_objective
import genesis_prime/game/held_objective
import genesis_prime/game/kill_objective
import genesis_prime/readiness
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/spawn.{type Row}
import gleam/erlang/process
import gleam/int
import gleam/result
import gleam/set.{type Set}
import gleam/string
import owned_key
import pog
import terrain_support

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

/// Every row of the spawn table of the database, read by the load's own query
/// (`content_spawn.rows`) on a checkout that lasts as long as the test does.
/// A query on its own is dropped after pgo's 5,000 ms for a checkout, the whole
/// read included. The read of the whole world database (77,794 rows) takes 63
/// to 96 ms in Postgres and 0.5 to 0.7 s on a Mac, also with four reads at once,
/// most of it the pool's and pog's decoding on the BEAM's schedulers. CI's
/// world-data part, which imports the same file and reads it in four tests at
/// once, took 154 to 268 s where a Mac takes 12 s, 13 to 22 times as long, which
/// puts the read past 5,000 ms (`query_timeout`). The test's own deadline
/// (`owned_test.run`) is the limit that applies, as for `database_support.execute`.
pub fn stored_spawns(database database: String) -> List(Row) {
  let assert Ok(rows) =
    dev_database.transaction(
      db: connect(database:),
      deadline_ms: ask_support.beyond_the_test_ms,
      work: content_spawn.rows,
    )
    as "the stored spawn rows read back"
  rows
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

/// The load with the way it asks the pool chosen by the test, over flat ground for every
/// square a spawn stands in.
pub fn load_asking(
  database database: String,
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
) -> #(Result(Nil, content.LoadError), table_store.Key) {
  load_with(database:, ask:, probe:, terrain: terrain_support.flat_reader())
}

/// The load with the ground read by the test's own reader.
pub fn load_terrain(
  database database: String,
  terrain terrain: content_terrain.Reader,
) -> #(Result(Nil, content.LoadError), table_store.Key) {
  load_with(database:, ask: asking(), probe: content.pool_probe, terrain:)
}

fn load_with(
  database database: String,
  ask ask: readiness.Settings,
  probe probe: fn(pog.Connection) -> readiness.Probe,
  terrain terrain: content_terrain.Reader,
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
      terrain:,
      key:,
    ),
    key,
  )
}

/// The content terms the key holds, each as its table's name and its id, in order.
@external(erlang, "content_support_ffi", "terms")
pub fn terms(key: table_store.Key) -> List(#(String, Int))

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

/// The QuestObjective ids the migrated database holds in the arrival table, read from a
/// database of the test's own.
pub fn arrival_objective_ids() -> Set(Int) {
  objective_ids(table: arrival_objective.table)
}

/// The QuestObjective ids the migrated database holds in the kill table, read from a
/// database of the test's own.
pub fn kill_objective_ids() -> Set(Int) {
  objective_ids(table: kill_objective.table)
}

/// The QuestObjective ids the migrated database holds as held, read from a database of
/// the test's own.
pub fn held_objective_ids() -> Set(Int) {
  objective_ids(table: held_objective.table)
}

fn objective_ids(table table: String) -> Set(Int) {
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) = objective_set.rows(db: connect(database:))
    as "the query ran"
  set.from_list(objective_set.ids(rows:, table:))
}
