//// The database pool's three settings, `pool_size`, `queue_target` and
//// `queue_interval` (`genesis_prime.pool_settings`). Expected values come from
//// these places.
//// - pog 4.1.0's `default_config`, the values the pool had before the settings
////   were named: pool_size 10, queue_target 50 ms, queue_interval 1000 ms.
//// - The settings are the server's choice, so a test of a pool uses values the
////   server does not: 3, 77 and 2222.
//// - Postgres's own count of the connections open on a database
////   (`pg_stat_activity`) says how many connections the pool kept.

import database_support
import genesis_prime.{PoolSettings}
import gleam/bool
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
  let settings = shared.settings
  let config =
    genesis_prime.pool_with(sizes:)
    |> pog.host(settings.tcp_host)
    |> pog.port(settings.port)
    |> pog.database(database)
    |> pog.user(settings.user)
    |> pog.password(settings.password)
    |> pog.ip_version(case string.contains(settings.tcp_host, ":") {
      True -> pog.Ipv6
      False -> pog.Ipv4
    })
  assert config.pool_size == 3
  assert config.queue_target == 77
  assert config.queue_interval == 2222
  let assert Ok(started) = pog.start(config) as "the pool started"
  process.unlink(started.pid)
  let pool = started.data
  await_connections(shared:, database:, count: 3, attempts: 500)
  list.each(list.repeat(Nil, 20), fn(_) {
    let assert Ok(_) = pog.query("select 1") |> pog.execute(pool)
      as "the pool ran a query"
  })
  assert connections(shared:, database:) == 3
    as "the pool keeps its size's connections, no more, though it ran more queries than that"
  process.kill(started.pid)
}

/// How many connections are open on `database`.
fn connections(
  shared shared: database_support.Shared,
  database database: String,
) -> Int {
  let assert Ok(pog.Returned(rows: [count], ..)) =
    pog.query("select count(*) from pg_stat_activity where datname = $1")
    |> pog.parameter(pog.text(database))
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(shared.admin)
    as "Postgres counts the connections"
  count
}

/// Waits until `count` connections are open on `database`, polling Postgres's
/// own count; a pool opens its connections after it starts. The test fails
/// when they are not open after `attempts` polls.
fn await_connections(
  shared shared: database_support.Shared,
  database database: String,
  count count: Int,
  attempts attempts: Int,
) -> Nil {
  use <- bool.guard(connections(shared:, database:) >= count, Nil)
  assert attempts > 0
    as { "the pool did not open " <> int.to_string(count) <> " connections" }
  process.sleep(20)
  await_connections(shared:, database:, count:, attempts: attempts - 1)
}
