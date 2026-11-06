//// The developer's database as the tools that add rows to it reach it
//// (`genesis_prime/add_account`, `genesis_prime/add_character`): the pool of
//// the server's own settings, from PGHOST, PGPORT, PGUSER, PGPASSWORD and
//// PGDATABASE (`genesis_prime.pool`), and one query run on it.

import genesis_prime
import genesis_prime/dev_exit
import genesis_prime/store/ready_pool
import gleam/io
import gleam/result
import pog

/// Why a query on the developer's database gave no rows.
pub type Failure {
  /// The pool could not start or never had a connection.
  DatabaseDown
  /// The database refused the change, naming the constraint.
  Refused(constraint: String)
  /// The query failed for another reason.
  NotChanged(reason: String)
  /// The query ran out of time, so the change may have been made.
  TimedOut
}

/// Starts the pool and waits until it has a connection, so the first query is
/// not answered as unavailable: gives the pool.
pub fn connect() -> Result(pog.Connection, Failure) {
  ready_pool.connect(genesis_prime.pool())
  |> result.map_error(failure_of_pool)
}

/// Starts the pool and runs the query on it, giving its rows.
pub fn run(
  query: fn(pog.Connection) -> Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Failure) {
  case pog.start(genesis_prime.pool()) {
    Error(_) -> Error(DatabaseDown)
    Ok(started) ->
      ready_pool.run(pool: started.data, query:)
      |> result.map_error(failure_of_pool)
  }
}

fn failure_of_pool(failure: ready_pool.Failure) -> Failure {
  case failure {
    ready_pool.NotStarted -> DatabaseDown
    ready_pool.QueryFailed(error:) -> failure_of(error:)
  }
}

/// The failure a query's error is, for a tool that runs its queries on a pool
/// of its own (`connect`).
pub fn failure_of(error error: pog.QueryError) -> Failure {
  case error {
    pog.ConstraintViolated(constraint:, ..) -> Refused(constraint:)
    pog.QueryTimeout -> TimedOut
    pog.ConnectionUnavailable -> DatabaseDown
    pog.PostgresqlError(name:, message:, ..) ->
      NotChanged(name <> ": " <> message)
    pog.UnexpectedArgumentCount(..)
    | pog.UnexpectedArgumentType(..)
    | pog.UnexpectedResultType(..) ->
      NotChanged("the query and the table do not match")
  }
}

/// How long a checkout of a connection, and a query, is allowed when none names
/// another: 5,000 ms, pgo's deadline for a checkout (`pgo_pool.erl`, `TIMEOUT`)
/// and pog's timeout for a query (`pog.timeout`'s doc).
pub const default_timeout_ms = 5000

/// Why a transaction did not commit.
pub type TransactionFailure(error) {
  /// The work gave this error, so the transaction was rolled back.
  Undone(error: error)
  /// The pool had no connection to run it on.
  NoConnection
  /// `begin`, `commit` or the rollback failed, as pog's own transaction
  /// reports it.
  Failed(error: pog.QueryError)
  /// The connection is a single connection (pog's callback gives one), which
  /// has no checkout to give a deadline.
  NotAPool
}

/// Runs `work` in one transaction on the pool `db`, whose connection may stay
/// checked out for `deadline_ms` in all, and commits when `work` gives `Ok`. The
/// work runs its queries on `db`, as outside a transaction. `pog.transaction`
/// is not used because its checkout is dropped by the pool after 5,000 ms
/// whatever the transaction has left to do, and pog has no option for another
/// deadline; a tool whose transaction grows with its file names its own.
@external(erlang, "dev_database_ffi", "transaction")
pub fn transaction(
  db db: pog.Connection,
  deadline_ms deadline_ms: Int,
  work work: fn(pog.Connection) -> Result(value, error),
) -> Result(value, TransactionFailure(error))

/// A sentence that says why a query failed; `change` is what the tool tried,
/// as in "add the account".
pub fn describe(failure failure: Failure, change change: String) -> String {
  case failure {
    DatabaseDown ->
      "the database could not be reached: check PGHOST, PGPORT, PGUSER, PGPASSWORD and PGDATABASE"
    Refused(constraint:) ->
      "the database refused to " <> change <> ": " <> constraint
    NotChanged(reason:) -> "could not " <> change <> ": " <> reason
    TimedOut ->
      "the database gave no answer in time to "
      <> change
      <> ": it may have been done, so look before trying again"
  }
}

/// Ends a developer tool: prints what the tool did on success, or the
/// sentence `describe` gives for its failure on the error stream and halts
/// with status 1.
pub fn finish(
  result result: Result(String, failure),
  describe describe: fn(failure) -> String,
) -> Nil {
  case result {
    Ok(done) -> io.println(done)
    Error(failure) -> {
      io.println_error(describe(failure))
      dev_exit.halt(1)
    }
  }
}
