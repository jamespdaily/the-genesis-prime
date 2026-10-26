//// The database pool is a child of the top supervisor that starts before the
//// children that use it. Expected values come from four places.
//// - OTP's supervisor behaviour (OTP design principles, "Supervisor
////   Behaviour"; `supervisor.erl` of OTP 29.1.2): children are started in the
////   order they are listed, and a one for one supervisor restarts only the
////   child that failed.
//// - The issue: the pool is started before any child that uses it, and the
////   tree starts and recovers with the database away and back.
//// - `pgo`'s source in `build/packages/pgo/src`: a connection whose attempt
////   fails waits before the next one, a wait that starts at 1000 ms, doubles
////   and stops growing at 10000 ms (`pgo_connection.erl` line 71,
////   `backoff:init(1000, 10000)`; `backoff.erl`, `fail/1` and `increment/2`),
////   and a query that finds no connection gets `none_available`
////   (`pgo_pool.erl`, `drop/2`), which `pog` reports as `ConnectionUnavailable`
////   (`pog_ffi.erl`, `convert_error/1`).
//// - Postgres: `select current_database()` returns the name of the database
////   the connection is to.
////
//// Each test has a database of its own and pool names of its own. The tests
//// wait for the events they need; the two waits with a deadline are the ones
//// whose event no message announces, and each says why.

import genesis_prime/database/pool
import genesis_prime/game/service as game_service
import genesis_prime/server
import gleam/dynamic/decode
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import owned_test
import pog
import relay
import supervisor_children
import template_database

/// How long a wait for one event that must happen at once may take, in
/// milliseconds.
const event_wait_ms = 5000

/// The longest a connection of the pool waits between two attempts to connect:
/// the 10000 ms at which `pgo`'s backoff stops growing (`pgo_connection.erl`
/// line 71). Once the database is back, the next attempt starts within this.
const longest_wait_between_attempts_ms = 10_000

/// What one attempt that succeeds may add to the wait: the connection's
/// handshake with a Postgres on the same machine.
const connection_setup_ms = 1000

pub fn the_pool_starts_before_every_other_child_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run

  // The tree `server.start` starts lists the pool first.
  let settings = pool_settings(database, "pool_first")
  let assert Ok(started) =
    server.start(template_database.tree_settings(settings))
    as "the top supervisor did not start"
  let assert [first, ..] = supervisor_children.in_start_order(started.pid)
    as "the top supervisor has no child"
  assert process.named(settings.name) == Ok(first)
    as "the first child is not the pool"

  // A child added after the pool queries it as it starts, and gets an answer.
  let planted_settings = pool_settings(database, "pool_before_a_user")
  let answers = process.new_subject()
  let assert Ok(planted) =
    server.supervisor_with_pool(planted_settings)
    |> static_supervisor.add(
      supervision.worker(fn() { start_user(planted_settings, answers) })
      |> supervision.timeout(1000),
    )
    |> static_supervisor.start
    as "the planted top supervisor did not start"
  assert process.receive(answers, event_wait_ms) == Ok(Ok([1]))
    as "the child added after the pool did not get an answer as it started"
  let assert [pool_pid, user_pid] =
    supervisor_children.in_start_order(planted.pid)
    as "the planted top supervisor does not have the pool and the user"
  assert process.named(planted_settings.name) == Ok(pool_pid)
    as "the first child of the planted tree is not the pool"
  assert user_pid != pool_pid
}

pub fn the_children_of_a_planted_supervisor_read_back_in_the_order_they_started_test() -> Nil {
  use <- owned_test.run(5000)
  let starts = process.new_subject()
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(
      supervision.worker(fn() { start_reporting(starts) }),
    )
    |> static_supervisor.add(
      supervision.worker(fn() { start_reporting(starts) }),
    )
    |> static_supervisor.add(
      supervision.worker(fn() { start_reporting(starts) }),
    )
    |> static_supervisor.start
    as "the planted supervisor did not start"
  let assert Ok(first) = process.receive(starts, 0)
    as "the first child did not report its start"
  let assert Ok(second) = process.receive(starts, 0)
    as "the second child did not report its start"
  let assert Ok(third) = process.receive(starts, 0)
    as "the third child did not report its start"
  assert supervisor_children.in_start_order(started.pid)
    == [first, second, third]
}

pub fn the_tree_starts_with_the_database_away_and_a_query_gets_an_error_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(away) = relay.refusing(to: target_of(database))
    as "the relay did not get a port"
  let settings = through(pool_settings(database, "pool_away"), away)

  let assert Ok(started) =
    server.start(template_database.tree_settings(settings))
    as "the tree did not start with the database away"
  assert process.is_alive(started.pid)
  let assert Ok(pool_pid) = process.named(settings.name)
    as "the pool is not running"
  assert process.is_alive(pool_pid)

  assert read_one(pool.connection(settings)) == Error(pog.ConnectionUnavailable)
    as "a query with the database away did not get a connection error"
  assert process.is_alive(pool_pid) as "the pool stopped"
  assert process.is_alive(started.pid) as "the top supervisor stopped"
}

pub fn the_database_coming_back_is_used_within_the_pools_reconnect_time_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let assert Ok(away) = relay.refusing(to: target_of(database))
    as "the relay did not get a port"
  let settings = through(pool_settings(database, "pool_back"), away)
  let assert Ok(_) = server.start(template_database.tree_settings(settings))
    as "the tree did not start with the database away"
  let connection = pool.connection(settings)
  assert read_one(connection) == Error(pog.ConnectionUnavailable)
    as "the database was not away"

  let assert Ok(Nil) = relay.forward(away) as "the relay did not start"
  // No message announces that a connection has been made: the pool's
  // connections retry on their own timers, so the only way to see the
  // database used again is to ask until an answer comes, up to the longest
  // wait between two attempts and one handshake.
  assert read_one_within(
      connection,
      longest_wait_between_attempts_ms + connection_setup_ms,
    )
    == Ok([1])
    as "the pool did not use the database again within its reconnect time"
}

pub fn a_pool_that_crashes_is_restarted_alone_and_its_users_carry_on_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let settings = pool_settings(database, "pool_crashing")
  let answers = process.new_subject()
  let assert Ok(started) =
    server.supervisor_with_pool(settings)
    |> static_supervisor.add(
      supervision.worker(fn() { start_user(settings, answers) })
      |> supervision.timeout(1000),
    )
    |> static_supervisor.start
    as "the planted top supervisor did not start"
  assert process.receive(answers, event_wait_ms) == Ok(Ok([1]))
  let connection = pool.connection(settings)
  assert read_one(connection) == Ok([1])
  let assert [old_pool, user] = supervisor_children.in_start_order(started.pid)
    as "the planted top supervisor does not have the pool and the user"

  let down = process.monitor(old_pool)
  process.kill(old_pool)
  let assert Ok(Nil) =
    process.new_selector()
    |> process.select_specific_monitor(down, fn(_down) { Nil })
    |> process.selector_receive(within: event_wait_ms)
    as "the pool did not stop"

  let assert Ok(new_pool) = wait_for_a_new_pool(settings.name, old_pool)
    as "the top supervisor did not restart the pool"
  assert new_pool != old_pool
  assert read_one(connection) == Ok([1])
    as "a query through the pool's name did not succeed after the restart"
  assert supervisor_children.in_start_order(started.pid) == [new_pool, user]
    as "the restart replaced a child other than the pool"
  assert process.is_alive(started.pid)
}

pub fn two_trees_with_different_pool_settings_do_not_share_a_pool_test() -> Nil {
  use <- owned_test.run(60_000)
  use first_database <- template_database.run
  use second_database <- template_database.run
  let first = pool_settings(first_database, "pool_first_tree")
  let second = pool_settings(second_database, "pool_second_tree")
  let assert Ok(_) = server.start(template_database.tree_settings(first))
    as "the first tree did not start"
  let assert Ok(_) = server.start(template_database.tree_settings(second))
    as "the second tree did not start"

  assert first_database.name != second_database.name
  assert read_database_name(pool.connection(first)) == Ok([first_database.name])
  assert read_database_name(pool.connection(second))
    == Ok([second_database.name])
  assert process.named(first.name) != process.named(second.name)
}

/// The settings of a pool of 2 connections to the test's own database, named
/// `name` plus a part made for the call.
fn pool_settings(
  database: template_database.Database,
  name: String,
) -> pool.Settings {
  template_database.pool_settings(
    for: database,
    pool_name: process.new_name(name),
    pool_size: 2,
  )
}

fn target_of(database: template_database.Database) -> relay.Target {
  relay.Target(host: database.settings.tcp_host, port: database.settings.port)
}

/// The same pool settings, connecting through the relay.
fn through(settings: pool.Settings, relay: relay.Relay) -> pool.Settings {
  pool.Settings(..settings, host: relay.host, port: relay.port)
}

/// What `select 1` returns through the connection.
fn read_one(connection: pog.Connection) -> Result(List(Int), pog.QueryError) {
  pog.query("select 1")
  |> pog.returning(decode.at([0], decode.int))
  |> pog.execute(on: connection)
  |> result.map(fn(returned) { returned.rows })
}

fn read_database_name(
  connection: pog.Connection,
) -> Result(List(String), pog.QueryError) {
  pog.query("select current_database()")
  |> pog.returning(decode.at([0], decode.string))
  |> pog.execute(on: connection)
  |> result.map(fn(returned) { returned.rows })
}

/// Asks `read_one` until it succeeds, for at most `within_ms`; the answer of
/// the last attempt when none succeeds. A timer sends the end of the wait, so
/// no clock is read and no time is slept.
fn read_one_within(
  connection: pog.Connection,
  within_ms: Int,
) -> Result(List(Int), pog.QueryError) {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, within_ms, Nil)
  read_one_until(connection, expired)
}

fn read_one_until(
  connection: pog.Connection,
  expired: Subject(Nil),
) -> Result(List(Int), pog.QueryError) {
  case read_one(connection) {
    Ok(rows) -> Ok(rows)
    Error(error) ->
      case process.receive(expired, 0) {
        Ok(Nil) -> Error(error)
        Error(Nil) -> read_one_until(connection, expired)
      }
  }
}

/// The pid the name is registered to once it is not `old`. The restarted pool
/// registers its name as it starts, and nothing announces that, so the name is
/// looked up until it names a new process, for at most `event_wait_ms`.
fn wait_for_a_new_pool(name: Name(pog.Message), old: Pid) -> Result(Pid, Nil) {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, event_wait_ms, Nil)
  look_for_a_new_pool(name:, old:, expired:)
}

fn look_for_a_new_pool(
  name name: Name(pog.Message),
  old old: Pid,
  expired expired: Subject(Nil),
) -> Result(Pid, Nil) {
  case process.named(name), process.receive(expired, 0) {
    Ok(pid), _ if pid != old -> Ok(pid)
    _, Error(Nil) -> look_for_a_new_pool(name:, old:, expired:)
    _, Ok(Nil) -> Error(Nil)
  }
}

/// A child that queries the pool as it starts and reports the answer.
fn start_user(
  settings: pool.Settings,
  answers: Subject(Result(List(Int), pog.QueryError)),
) -> Result(actor.Started(Subject(Nil)), actor.StartError) {
  actor.new_with_initialiser(event_wait_ms * 2, fn(subject) {
    process.send(answers, read_one(pool.connection(settings)))
    Ok(actor.initialised(Nil) |> actor.returning(subject))
  })
  |> actor.on_message(fn(state, _message: Nil) { actor.continue(state) })
  |> actor.start
}

/// A child that reports its own pid when it starts.
fn start_reporting(
  starts: Subject(Pid),
) -> Result(actor.Started(Subject(Nil)), actor.StartError) {
  actor.new_with_initialiser(event_wait_ms, fn(subject) {
    process.send(starts, process.self())
    Ok(actor.initialised(Nil) |> actor.returning(subject))
  })
  |> actor.on_message(fn(state, _message: Nil) { actor.continue(state) })
  |> actor.start
}

pub fn the_pools_connections_stop_a_statement_before_the_game_workers_deadline_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let settings = pool_settings(database, "pool_statement_limit")
  let assert Ok(_) =
    server.supervisor_with_pool(settings) |> static_supervisor.start
    as "the planted top supervisor did not start"
  let assert Ok(pog.Returned(rows: [limit], ..)) =
    pog.query("select current_setting('statement_timeout')")
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(on: pool.connection(settings))
    as "the setting was read"
  assert limit == "4s"
    as "designing-processes: a write past the worker's deadline of 5 seconds (game/service) may still commit, so Postgres cancels a statement at 4 seconds, before the worker is killed"
  assert pool.statement_timeout_ms < game_service.answer_deadline_ms
    as "the pool's limit is below the workers' deadline"
}

pub fn the_wait_for_a_connection_the_statement_limit_and_the_margin_end_before_the_workers_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  assert pool.checkout_wait_bound_ms
    + pool.statement_timeout_ms
    + pool.margin_ms
    < game_service.answer_deadline_ms
    as "a write that was reported failed has committed nothing: a worker that has no connection is killed at its deadline, and one that has a connection is waited for up to the statement's limit and the margin, so the longest wait for a connection and then the wait for the answer must end before the asker's deadline"
  assert pool.checkout_wait_bound_ms == 3 * pool.queue_interval_ms
    as "pgo_pool.erl: a request that waits in a pool whose connections are all held is refused at the third poll after it arrived, so at most 3 queue intervals"
}
