//// The transaction the developer tools run with a deadline of their own
//// (`genesis_prime/dev_database.transaction`). Expected values come from these
//// places.
//// - The pool drops the connection of a checkout held past its deadline, and a
////   query on it then gives pog's `QueryTimeout` (pgo's `pgo_pool.erl`, the
////   timer that disconnects the holder with `client_timeout`; pog's
////   `convert_error(closed)`).
//// - Postgres's documentation of deferrable constraints: a deferred unique
////   constraint is checked at `commit`, which then fails with SQLSTATE 23505
////   under the constraint's own name (the default `<table>_<column>_key`).
//// - pog's own transaction (`pog.transaction`): a failed `commit` is the query
////   error it gave, never a crash.
//// Each test runs on a database of its own, copied from the migrated template.

import content_support
import database_support
import genesis_prime/dev_database.{Failed, NotAPool}
import gleam/result
import owned_test
import pog
import unitest

/// A database of the test's own and a pool on it.
fn pool() -> #(String, pog.Connection) {
  let database = database_support.new_database(on: database_support.shared())
  #(database, content_support.connect(database:))
}

pub fn a_transaction_held_past_its_deadline_gives_a_query_timeout_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("dev_tool")
  let #(_database, db) = pool()
  // The deadline is 100 ms and the one statement takes 500 ms, a margin a slow
  // machine only widens. That a deadline above 5,000 ms is honoured as well
  // is not tested: it would take more than 5 s.
  let result =
    dev_database.transaction(db:, deadline_ms: 100, work: fn(tx) {
      pog.query("select pg_sleep(0.5)")
      |> pog.execute(tx)
      |> result.replace(Nil)
    })
  assert result == Error(Failed(pog.QueryTimeout))
    as "the pool dropped the connection at the deadline the transaction named, so the statement and then the rollback timed out, the rollback being what pog reports"
}

pub fn a_transaction_whose_commit_fails_gives_the_query_error_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("dev_tool")
  let #(database, db) = pool()
  content_support.psql(
    database:,
    sql: "create table commit_probe (n int unique deferrable initially deferred)",
  )
  let result =
    dev_database.transaction(db:, deadline_ms: 60_000, work: fn(tx) {
      pog.query("insert into commit_probe values (1), (1)")
      |> pog.execute(tx)
      |> result.replace(Nil)
    })
  let assert Error(dev_database.Failed(pog.ConstraintViolated(constraint:, ..))) =
    result
    as "the commit's refusal is the query error pog gave"
  assert constraint == "commit_probe_n_key"
  assert content_support.count(
      database:,
      sql: "select count(*) from commit_probe",
    )
    == 0
    as "nothing was committed"
}

pub fn a_transaction_on_a_single_connection_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("dev_tool")
  let #(_database, db) = pool()
  // pog hands its callback a single connection, which has no checkout to name
  // a deadline for.
  let result =
    pog.transaction(db, fn(single) {
      Ok(
        dev_database.transaction(db: single, deadline_ms: 60_000, work: fn(_) {
          Ok(Nil)
        }),
      )
    })
  assert result == Ok(Error(NotAPool)) as "refused by its name, not a crash"
}
