//// The workers that carry out character select's commands: a command run in a
//// worker gives the answer the store gives, a database that cannot be reached
//// gives `Unavailable`, and a worker that has not answered by the deadline is
//// stopped and gives `Unavailable` (designing-processes: lookups and saves run
//// in supervised workers with deadlines, and a request carries a deadline).
//// Each test has a database of its own.

import freezing_relay
import genesis_prime/character/character.{Appearance, NewCharacter, Place}
import genesis_prime/character/select.{Inserted, Loaded, Unavailable}
import genesis_prime/character/store
import genesis_prime/character/store_worker.{Workers}
import genesis_prime/connection/clock
import genesis_prime/database/pool
import genesis_prime/login/account_store
import genesis_prime/map/position.{Position}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/otp/static_supervisor
import map_support
import owned_test
import pog
import supervisor_children
import template_database

const answer_wait_ms = 5000

fn start_workers() -> store_worker.Workers {
  let workers = Workers(factory: process.new_name("store_workers"))
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(store_worker.supervised(workers))
    |> static_supervisor.start
    as "the workers did not start"
  workers
}

fn new_character(account_id: Int) -> character.NewCharacter {
  NewCharacter(
    account_id:,
    name: "Ab Cd",
    creation_id: 277,
    gender: 1,
    race_id: 1,
    class_id: 3,
    faction_id: 167,
    experience: 1710,
    level: 3,
    path: 2,
    place: Place(
      world_id: 51,
      world_zone_id: 9,
      position: Position(x: 1.0, y: -2.5, z: 100.25),
    ),
    appearance: Appearance(
      customisation_labels: [1, 2],
      customisation_values: [3, 4],
      bone_values: [0x3F800000, 0xBF000000],
    ),
  )
}

/// A pool of one connection to the test's database whose every insert of a
/// character takes `sleep` seconds, whose connection cancels a statement that
/// runs `limit_ms` milliseconds and ends a transaction that runs
/// `transaction_limit_ms` milliseconds. A limit of 0 is no limit.
fn start_slow_pool(
  database database: template_database.Database,
  sleep sleep: String,
  limit_ms limit_ms: Int,
  transaction_limit_ms transaction_limit_ms: Int,
) -> pog.Connection {
  let pool_name = process.new_name("slow_insert_pool")
  let assert Ok(_) =
    template_database.config(for: database, pool_name:, pool_size: 1)
    |> pog.start
    as "the pool of one connection started"
  let one = pog.named_connection(pool_name)
  list.each(
    [
      "create function slow_insert() returns trigger language plpgsql as $$ begin perform pg_sleep("
        <> sleep
        <> "); return new; end $$",
      "create trigger slow_insert before insert on character for each row execute function slow_insert()",
      "set statement_timeout = " <> int.to_string(limit_ms),
      "set transaction_timeout = " <> int.to_string(transaction_limit_ms),
    ],
    fn(statement) {
      let assert Ok(_) = pog.query(statement) |> pog.execute(on: one)
        as "the slow save was planted"
      Nil
    },
  )
  one
}

pub fn a_command_run_in_a_worker_gives_the_stores_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let command = select.LoadCharacters(account_id: account.id)
  assert store_worker.run(
      workers:,
      db: database.connection,
      command:,
      within_ms: answer_wait_ms,
    )
    == store.run(database.connection, command)
    as "a worker gives the answer the store gives"
  assert store_worker.run(
      workers:,
      db: database.connection,
      command:,
      within_ms: answer_wait_ms,
    )
    == Loaded([])
    as "a new account has no characters"
}

pub fn a_database_that_is_away_gives_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  let workers = start_workers()
  let away = pog.named_connection(process.new_name("no_pool_runs_here"))
  assert store_worker.run(
      workers:,
      db: away,
      command: select.LoadCharacters(account_id: 1),
      within_ms: answer_wait_ms,
    )
    == Unavailable
    as "designing-processes: a database that is away is an outside failure the caller handles"
}

pub fn a_worker_that_has_not_answered_by_the_deadline_gives_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let pool_name = process.new_name("one_connection_pool")
  let assert Ok(_) =
    template_database.config(for: database, pool_name:, pool_size: 1)
    |> pog.start
    as "the pool of one connection started"
  let one = pog.named_connection(pool_name)
  // A transaction holds the pool's only connection until the test lets it go,
  // so the worker's statement waits for a connection it cannot have.
  let holding = process.new_subject()
  process.spawn(fn() {
    let release = process.new_subject()
    let assert Ok(_) =
      pog.transaction(one, fn(_transaction) {
        process.send(holding, release)
        let assert Ok(Nil) = process.receive(release, 30_000)
          as "the test let the connection go"
        Ok(Nil)
      })
      as "the transaction ran"
    Nil
  })
  let assert Ok(release) = process.receive(holding, answer_wait_ms)
    as "the transaction holds the connection"
  assert store_worker.run(
      workers:,
      db: one,
      command: select.LoadCharacters(account_id: 1),
      within_ms: 300,
    )
    == Unavailable
    as "a worker that cannot get a connection by the deadline is stopped and the answer is Unavailable"
  process.send(release, Nil)
}

pub fn workers_whose_supervisor_is_not_running_give_unavailable_and_not_a_crash_test() -> Nil {
  use <- owned_test.run(60_000)
  // A supervisor that is being rebuilt has no process under its name.
  let workers = Workers(factory: process.new_name("store_workers_away"))
  assert store_worker.run(
      workers:,
      db: pog.named_connection(process.new_name("no_pool_runs_here")),
      command: select.LoadCharacters(account_id: 1),
      within_ms: answer_wait_ms,
    )
    == Unavailable
    as "designing-processes: a request to a process that is away is an outside failure the asker handles, not a crash of the asker"
}

pub fn a_write_that_has_no_connection_at_the_deadline_is_killed_before_it_sends_anything_and_commits_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("one_connection_pool_of_the_server"),
      pool_size: 1,
    )
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(pool.supervised(settings))
    |> static_supervisor.start
    as "the server's pool of one connection started"
  let one = pool.connection(settings)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  // A transaction holds the pool's only connection until the test lets it go,
  // so the worker's write waits for a connection in the pool's queue.
  let holding = process.new_subject()
  process.spawn(fn() {
    let release = process.new_subject()
    let assert Ok(_) =
      pog.transaction(one, fn(_transaction) {
        process.send(holding, release)
        let assert Ok(Nil) = process.receive(release, 30_000)
          as "the test let the connection go"
        Ok(Nil)
      })
      as "the transaction ran"
    Nil
  })
  let assert Ok(release) = process.receive(holding, answer_wait_ms)
    as "the transaction holds the connection"
  let answer =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: 500,
    )
  process.send(release, Nil)
  assert answer == Unavailable
    as "a write that has no connection by the deadline is reported failed"
  // The pool serves its queue in order, so once a read through the same pool
  // is answered, a write the killed worker had left in the queue would have
  // been carried out.
  assert store.run(one, select.LoadCharacters(account.id)) == Loaded([])
    as "designing-processes: a worker that held no connection was killed before it sent its statement, so nothing of the write committed"
}

pub fn a_write_that_holds_its_connection_and_runs_past_the_deadline_is_not_killed_and_reports_what_happened_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let one =
    start_slow_pool(
      database:,
      sleep: "0.8",
      limit_ms: 5000,
      transaction_limit_ms: 0,
    )
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let answer =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: 300,
    )
  let assert Inserted(saved) = answer
    as "designing-processes: a worker that holds a connection and has sent its statement is not killed at the first deadline, because the write can commit after it, so the answer is what the database did: here it committed, so the answer is the character"
  assert store.run(database.connection, select.LoadCharacters(account.id))
    == Loaded([saved])
    as "the answer says what is stored: the write that was reported done is committed"
}

pub fn a_write_the_database_cancels_after_the_deadline_gives_unavailable_and_commits_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let one =
    start_slow_pool(
      database:,
      sleep: "2",
      limit_ms: 300,
      transaction_limit_ms: 0,
    )
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let started = clock.monotonic_milliseconds()
  let answer =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: 100,
    )
  let waited = clock.monotonic_milliseconds() - started
  assert answer == Unavailable
    as "a write the database cancelled at its limit is reported failed"
  assert waited >= 300
    as "designing-processes: the worker holds its connection past the first deadline, so the answer is waited for until the database cancels the statement at its limit (error 57014), and is not a guess at the deadline"
  assert store.run(database.connection, select.LoadCharacters(account.id))
    == Loaded([])
    as "a write that was reported failed committed nothing"
}

pub fn a_write_the_database_ends_at_the_transactions_limit_gives_unknown_and_commits_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  // The statement's own limit is far off, so only the transaction's ends it.
  let one =
    start_slow_pool(
      database:,
      sleep: "2",
      limit_ms: 0,
      transaction_limit_ms: 300,
    )
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let started = clock.monotonic_milliseconds()
  let answer =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: 100,
    )
  let waited = clock.monotonic_milliseconds() - started
  assert answer == select.Unknown
    as "a write whose connection closed after the go may have committed, so it is not reported failed: Postgres ends the session at the transaction's limit (error 25P04, transaction_timeout) and closes the socket, which pog reports as a timeout (pog_ffi.erl:142-143), and Unavailable means nothing committed"
  assert waited >= 300 && waited < 1500
    as "the answer comes when the database closes the connection at the transaction's limit, and is not a guess at the asker's deadline"
  assert store.run(database.connection, select.LoadCharacters(account.id))
    == Loaded([])
    as "Postgres rolled back the transaction it ended, so nothing was stored"
}

/// Asks until Postgres runs an insert of a character in a session other than
/// the one that asks: the write has been sent, so its worker holds a
/// connection and was told to go. Gives up after `within_ms` milliseconds,
/// which a timer announces.
fn wait_for_the_insert_to_run(
  connection connection: pog.Connection,
  within_ms within_ms: Int,
) -> Bool {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, within_ms, Nil)
  insert_runs_until(connection, expired)
}

fn insert_runs_until(
  connection: pog.Connection,
  expired: process.Subject(Nil),
) -> Bool {
  let assert Ok(pog.Returned(rows: [running], ..)) =
    pog.query(
      "select count(*) from pg_stat_activity where datname = current_database() and pid <> pg_backend_pid() and state = 'active' and query ilike '%insert into character (%'",
    )
    |> pog.returning(decode.at([0], decode.int))
    |> pog.execute(on: connection)
    as "pg_stat_activity was read"
  case running > 0, process.receive(expired, 0) {
    True, _ -> True
    False, Ok(Nil) -> False
    False, Error(Nil) -> insert_runs_until(connection, expired)
  }
}

pub fn a_write_that_has_no_answer_when_the_longest_wait_ends_is_unknown_and_not_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  // The statement is sent and runs, and its worker then stops, so nothing
  // answers: neither the database's limits nor the worker's own timeout
  // reports back, as when a stalled network holds up the answer.
  let one =
    start_slow_pool(
      database:,
      sleep: "30",
      limit_ms: 0,
      transaction_limit_ms: 0,
    )
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let answered = process.new_subject()
  process.spawn(fn() {
    let started = clock.monotonic_milliseconds()
    let answer =
      store_worker.run(
        workers:,
        db: one,
        command: select.InsertCharacter(new_character(account.id)),
        within_ms: 100,
      )
    process.send(answered, #(answer, clock.monotonic_milliseconds() - started))
  })
  assert wait_for_the_insert_to_run(
    connection: database.connection,
    within_ms: answer_wait_ms,
  )
    as "the write was sent to the database"
  let assert Ok(factory) = process.named(workers.factory)
    as "the workers' supervisor runs"
  let assert [worker] = supervisor_children.in_start_order(factory)
    as "one worker carries the write out"
  map_support.suspend(worker)
  let assert Ok(#(answer, waited)) =
    process.receive(answered, pool.holding_wait_ms() + answer_wait_ms)
    as "the asker gave an answer"
  process.kill(worker)
  assert answer == select.Unknown
    as "a write that was sent and has no answer may have committed, so it is not reported failed: the connection ends and the client lists again"
  assert waited >= pool.holding_wait_ms()
    as "the asker waits for the answer up to the longest a write can take, which is the transaction's limit and the margin"
  assert waited < pool.holding_wait_ms() + 1000
    as "the wait ends at that ceiling and is not for ever"
}

pub fn a_worker_that_ends_without_answering_after_it_was_told_to_go_is_unknown_and_not_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  // The statement is sent and runs, and the worker is then killed before it
  // answers: its statement may have reached Postgres and may commit.
  let one =
    start_slow_pool(
      database:,
      sleep: "30",
      limit_ms: 0,
      transaction_limit_ms: 0,
    )
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let answered = process.new_subject()
  process.spawn(fn() {
    process.send(
      answered,
      store_worker.run(
        workers:,
        db: one,
        command: select.InsertCharacter(new_character(account.id)),
        within_ms: 100,
      ),
    )
  })
  assert wait_for_the_insert_to_run(
    connection: database.connection,
    within_ms: answer_wait_ms,
  )
    as "the write was sent to the database"
  let assert Ok(factory) = process.named(workers.factory)
    as "the workers' supervisor runs"
  let assert [worker] = supervisor_children.in_start_order(factory)
    as "one worker carries the write out"
  process.kill(worker)
  let assert Ok(answer) = process.receive(answered, answer_wait_ms)
    as "the asker gave an answer as soon as its worker ended"
  assert answer == select.Unknown
    as "a worker that was told to go and ended without answering may have sent its statement, so nothing is known to be uncommitted"
}

/// A pool of one connection to the test's database through a relay that
/// freezes the connection that sends an insert of a character: the insert
/// reaches Postgres and nothing passes either way after it, while the relay's
/// new connections work as before.
fn start_pool_through_freezing_relay(
  database database: template_database.Database,
) -> #(pog.Connection, freezing_relay.Relay) {
  let assert Ok(relay) =
    freezing_relay.start(
      to: freezing_relay.Target(
        host: database.settings.tcp_host,
        port: database.settings.port,
      ),
      freezing_on: "insert into character (",
    )
    as "the freezing relay started"
  let pool_name = process.new_name("pool_through_the_freezing_relay")
  let assert Ok(_) =
    template_database.config(for: database, pool_name:, pool_size: 1)
    |> pog.host(relay.host)
    |> pog.port(relay.port)
    |> pog.start
    as "the pool of one connection through the relay started"
  #(pog.named_connection(pool_name), relay)
}

pub fn a_write_whose_database_stops_answering_after_the_go_gives_unknown_and_not_unavailable_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let #(one, relay) = start_pool_through_freezing_relay(database:)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let answer =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: answer_wait_ms,
    )
  assert option.is_some(freezing_relay.frozen_connection(relay))
    as "the relay froze the connection after the insert was sent, so the database stopped answering with its link open"
  assert answer == select.Unknown
    as "a write whose link closed after the go may have committed, so it is not Unavailable: pgo ends a checkout at its deadline of 5000 ms (pgo_pool.erl:19,283-289), which closes the socket (pgo_pool.erl:149-158), pog reports the closed socket as a timeout (pog_ffi.erl:142-143), and Unavailable means nothing committed"
}

pub fn after_a_write_whose_database_stopped_answering_the_pool_of_one_serves_the_next_command_on_a_new_connection_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let #(one, relay) = start_pool_through_freezing_relay(database:)
  let assert Ok(account) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let _answer_of_the_write =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: answer_wait_ms,
    )
  let assert Some(frozen) = freezing_relay.frozen_connection(relay)
    as "the relay froze the connection after the insert was sent"
  assert store_worker.run(
      workers:,
      db: one,
      command: select.LoadCharacters(account_id: account.id),
      within_ms: 10_000,
    )
    == Loaded([])
    as "the pool's deadline of 5000 ms freed the frozen connection (pgo_pool.erl:149-158), so the next command is answered, and the write that never committed is not listed"
  assert freezing_relay.opened(relay) > frozen
    as "the answer came over a connection opened after the frozen one, which the pool made again when it ended the first (pgo_connection.erl:83-96)"
}
