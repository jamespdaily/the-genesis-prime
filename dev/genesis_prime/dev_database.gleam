//// The developer's database as the tools that add rows to it reach it
//// (`genesis_prime/add_account`, `genesis_prime/add_character`): the pool of
//// the server's own settings, from PGHOST, PGPORT, PGUSER, PGPASSWORD and
//// PGDATABASE (`genesis_prime.pool`), and one query run on it.

import genesis_prime
import gleam/erlang/process
import gleam/io
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

/// How many times the query is tried while the pool has no connection yet: it
/// opens its connections after it starts, and a query made before one is open
/// is answered as unavailable, without having run. A query that timed out may
/// have run, so it is never tried again.
const connection_attempts = 5

/// How long to wait before trying again, in milliseconds.
const connection_wait_ms = 100

/// Starts the pool and runs the query on it, giving its rows.
pub fn run(
  query: fn(pog.Connection) -> Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Failure) {
  case pog.start(genesis_prime.pool()) {
    Error(_) -> Error(DatabaseDown)
    Ok(started) ->
      attempt(pool: started.data, query:, attempts: connection_attempts)
  }
}

fn attempt(
  pool pool: pog.Connection,
  query query: fn(pog.Connection) -> Result(pog.Returned(row), pog.QueryError),
  attempts attempts: Int,
) -> Result(List(row), Failure) {
  case query(pool) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(pog.ConstraintViolated(constraint:, ..)) ->
      Error(Refused(constraint:))
    Error(pog.QueryTimeout) -> Error(TimedOut)
    Error(pog.ConnectionUnavailable) ->
      case attempts > 1 {
        True -> {
          process.sleep(connection_wait_ms)
          attempt(pool:, query:, attempts: attempts - 1)
        }
        False -> Error(DatabaseDown)
      }
    Error(pog.PostgresqlError(name:, message:, ..)) ->
      Error(NotChanged(name <> ": " <> message))
    Error(pog.UnexpectedArgumentCount(..))
    | Error(pog.UnexpectedArgumentType(..))
    | Error(pog.UnexpectedResultType(..)) ->
      Error(NotChanged("the query and the table do not match"))
  }
}

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
      halt(1)
    }
  }
}

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil
