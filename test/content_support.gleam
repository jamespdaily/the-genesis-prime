//// What the tests of the content tables share: a connection to a database of the
//// test's own, and the fixture of the world database.

import database_support
import event_wait
import gleam/erlang/process
import gleam/int
import gleam/result
import gleam/string
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
