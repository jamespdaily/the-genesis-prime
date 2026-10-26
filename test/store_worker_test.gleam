//// The workers that carry out character select's commands: a command run in a
//// worker gives the answer the store gives, a database that cannot be reached
//// gives `Unavailable`, and a worker that has not answered by the deadline is
//// stopped and gives `Unavailable` (designing-processes: lookups and saves run
//// in supervised workers with deadlines, and a request carries a deadline).
//// Each test has a database of its own.

import genesis_prime/character/character.{Appearance, NewCharacter, Place}
import genesis_prime/character/select.{Inserted, Loaded, Unavailable}
import genesis_prime/character/store
import genesis_prime/character/store_worker.{Workers}
import genesis_prime/connection/clock
import genesis_prime/database/pool
import genesis_prime/game/service as game_service
import genesis_prime/login/account_store
import genesis_prime/map/position.{Position}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/static_supervisor
import owned_test
import pog
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
/// character takes `sleep` seconds, and whose connection cancels a statement
/// that runs `limit_ms` milliseconds.
fn start_slow_pool(
  database: template_database.Database,
  sleep sleep: String,
  limit_ms limit_ms: Int,
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

pub fn a_write_that_waits_for_a_connection_is_refused_within_the_pools_bound_and_commits_nothing_test() -> Nil {
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
  let started = clock.monotonic_milliseconds()
  let answer =
    store_worker.run(
      workers:,
      db: one,
      command: select.InsertCharacter(new_character(account.id)),
      within_ms: game_service.answer_deadline_ms,
    )
  let waited = clock.monotonic_milliseconds() - started
  process.send(release, Nil)
  assert answer == Unavailable
    as "a write that cannot get a connection is reported failed"
  assert waited <= pool.checkout_wait_bound_ms + pool.margin_ms
    as "designing-processes: the pool refuses a request that waits for a connection after its checkout bound, so the worker is never killed at its deadline with a write that has begun: the wait, the statement's limit and the margin end before the worker's deadline"
  assert store.run(database.connection, select.LoadCharacters(account.id))
    == Loaded([])
    as "a write that was reported failed committed nothing"
}

pub fn a_write_that_holds_its_connection_and_runs_past_the_deadline_is_not_killed_and_reports_what_happened_test() -> Nil {
  use <- owned_test.run(60_000)
  use database <- template_database.run
  let workers = start_workers()
  let one = start_slow_pool(database, sleep: "0.8", limit_ms: 5000)
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
  let one = start_slow_pool(database, sleep: "2", limit_ms: 300)
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
