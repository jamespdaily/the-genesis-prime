//// The wait for a pool to have started. Expected values come from `pgo`'s
//// source in `build/packages/pgo/src`: the starter of a pool (`pgo_connection_starter.erl`)
//// opens the connections and then calls the type server, which loads the types
//// through a connection and, when it cannot, tries again every 500 ms
//// (`pgo_type_server.erl`), so with the database away the starter never
//// finishes; and a pool whose database answers finishes once its connections
//// are open.

import genesis_prime/database/pool
import gleam/erlang/process
import gleam/otp/static_supervisor
import owned_test
import pool_started
import relay
import template_database

/// How long a pool of a running database has to start: a handshake for each of
/// its connections on this machine, with room for a slow runner.
const start_ms = 20_000

/// How long the wait for a pool whose database is away runs before it says the
/// pool has not started: no event announces that nothing will happen.
const away_ms = 500

fn start_pool(settings: pool.Settings) -> Nil {
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(pool.supervised(settings))
    |> static_supervisor.start
    as "the pool did not start"
  Nil
}

pub fn a_pool_of_a_running_database_has_started_when_the_wait_returns_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("started_pool"),
      pool_size: 4,
    )
  start_pool(settings)
  assert pool_started.await(name: settings.name, within_ms: start_ms)
    as "pgo_connection_starter.erl: the starter finishes once the connections are open and the types are loaded"
}

pub fn a_pool_whose_database_is_away_has_not_started_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let assert Ok(away) =
    relay.refusing(to: relay.Target(
      host: database.settings.tcp_host,
      port: database.settings.port,
    ))
    as "the relay did not get a port"
  let settings =
    pool.Settings(
      ..template_database.pool_settings(
        for: database,
        pool_name: process.new_name("away_pool"),
        pool_size: 2,
      ),
      host: away.host,
      port: away.port,
    )
  start_pool(settings)
  assert !pool_started.await(name: settings.name, within_ms: away_ms)
    as "pgo_type_server.erl: with no connection the types cannot load, so the starter is still waiting for them"
}
