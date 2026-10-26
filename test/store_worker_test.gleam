//// The workers that carry out character select's commands: a command run in a
//// worker gives the answer the store gives, a database that cannot be reached
//// gives `Unavailable`, and a worker that has not answered by the deadline is
//// stopped and gives `Unavailable` (designing-processes: lookups and saves run
//// in supervised workers with deadlines, and a request carries a deadline).
//// Each test has a database of its own.

import genesis_prime/character/select.{Loaded, Unavailable}
import genesis_prime/character/store
import genesis_prime/character/store_worker.{Workers}
import genesis_prime/login/account_store
import gleam/erlang/process
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
    let _ =
      pog.transaction(one, fn(_transaction) {
        process.send(holding, release)
        let _ = process.receive(release, 30_000)
        Ok(Nil)
      })
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
