//// The database pool's three settings, `pool_size`, `queue_target` and
//// `queue_interval` (`genesis_prime.pool_settings`). Expected values come from
//// these places.
//// - pog 4.1.0's `default_config`, the values the pool had before the settings
////   were named: pool_size 10, queue_target 50 ms, queue_interval 1000 ms.
//// - The settings are the server's choice, so a test of a pool uses values the
////   server does not: 3, 77 and 2222.
//// - Postgres's own list of the backends open on a database
////   (`pg_stat_activity`) says which connections the pool kept.

import database_support
import event_wait
import genesis_prime.{PoolSettings}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import owned_test
import pog

pub fn the_servers_pool_has_the_three_named_settings_with_pogs_defaults_test() -> Nil {
  use <- owned_test.run(5000)
  assert genesis_prime.pool_settings
    == PoolSettings(pool_size: 10, queue_target: 50, queue_interval: 1000)
  let config = genesis_prime.pool()
  assert config.pool_size == 10
  assert config.queue_target == 50
  assert config.queue_interval == 1000
}

pub fn a_pool_made_with_other_settings_has_them_and_keeps_that_many_connections_test() -> Nil {
  use <- owned_test.run(60_000)
  let sizes = PoolSettings(pool_size: 3, queue_target: 77, queue_interval: 2222)
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let config =
    genesis_prime.pool_with(sizes:)
    |> database_support.connect_to(shared.settings, database:)
  assert config.pool_size == 3
  assert config.queue_target == 77
  assert config.queue_interval == 2222
  let assert Ok(started) = pog.start(config) as "the pool started"
  process.unlink(started.pid)
  let pool = started.data
  let pool_backends = hold_every_connection(pool, count: 3)
  list.each(list.repeat(Nil, 20), fn(_) {
    let assert Ok(_) = pog.query("select 1") |> pog.execute(pool)
      as "the pool ran a query"
  })
  await_backends(
    shared:,
    database:,
    are: pool_backends,
    because: "the pool keeps its size's connections, no more, though it ran more queries than that",
  )
  process.kill(started.pid)
}

/// The Postgres backends of `count` connections the pool holds at once, in
/// order: `count` processes each take a connection and report its backend,
/// and all are released once every one has reported. A pool with fewer
/// connections open than `count` answers when the last one opens, so the
/// backends are the pool's own however slowly it starts.
fn hold_every_connection(pool: pog.Connection, count count: Int) -> List(Int) {
  let reports = process.new_subject()
  list.each(list.repeat(Nil, count), fn(_) {
    process.spawn(fn() {
      let release = process.new_subject()
      let assert Ok(_) =
        pog.transaction(pool, fn(connection) {
          let assert Ok(pog.Returned(rows: [backend], ..)) =
            pog.query("select pg_backend_pid()")
            |> pog.returning(decode.at([0], decode.int))
            |> pog.execute(connection)
            as "the connection reported its backend"
          process.send(reports, #(backend, release))
          process.receive_forever(release)
          Ok(Nil)
        })
        as "the pool lent a connection"
    })
  })
  let held =
    list.map(list.repeat(Nil, count), fn(_) { process.receive_forever(reports) })
  list.each(held, fn(connection) { process.send(connection.1, Nil) })
  list.sort(list.map(held, fn(connection) { connection.0 }), int.compare)
}

/// The Postgres backends open on `database`, in order.
fn backends(
  shared shared: database_support.Shared,
  database database: String,
) -> List(Int) {
  let assert Ok(pog.Returned(rows:, ..)) =
    pog.query(
      "select pid from pg_stat_activity where datname = $1 order by pid",
    )
    |> pog.parameter(pog.text(database))
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(shared.admin)
    as "Postgres lists the backends"
  rows
}

/// Waits until the backends open on `database` are exactly `expected`, reading
/// Postgres's own list every millisecond: Postgres sends the test no event when
/// a backend closes. The pool's driver opens a short-lived connection of its own
/// to load the database's types, so another backend may be there for a moment;
/// one the pool keeps stays. The wait has no limit of its own: the test's
/// deadline ends it, naming `because` (`event_wait`).
fn await_backends(
  shared shared: database_support.Shared,
  database database: String,
  are expected: List(Int),
  because reason: String,
) -> Nil {
  event_wait.until(
    reason <> ": the backends open on the database to be " <> numbers(expected),
    fn() { backends(shared:, database:) == expected },
  )
}

/// The backend ids, comma-separated.
fn numbers(backends: List(Int)) -> String {
  string.join(list.map(backends, int.to_string), ", ")
}
