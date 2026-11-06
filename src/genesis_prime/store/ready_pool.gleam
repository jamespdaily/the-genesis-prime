//// A database pool for a tool or a start-up step that runs a few queries on a
//// pool of its own: pog opens a pool's connections after the pool starts, and
//// a query made before one is open is answered as unavailable without having
//// run, so a query is tried again while that is the answer.

import gleam/dynamic/decode
import gleam/erlang/process
import gleam/result
import pog

/// Why a pool gave no answer.
pub type Failure {
  /// The pool could not start.
  NotStarted
  /// The pool started and the query failed with this error.
  QueryFailed(error: pog.QueryError)
}

/// How many times a query is tried while the pool has no connection yet.
const connection_attempts = 5

/// How long to wait before trying again, in milliseconds.
const connection_wait_ms = 100

/// Starts the pool of this configuration and waits until it has a connection,
/// so the first query is not answered as unavailable: gives the pool.
pub fn connect(config: pog.Config) -> Result(pog.Connection, Failure) {
  case pog.start(config) {
    Error(_) -> Error(NotStarted)
    Ok(started) -> {
      use _ <- result.map(
        run(pool: started.data, query: fn(db) {
          pog.query("select 1")
          |> pog.returning(decode.at([0], decode.int))
          |> pog.execute(db)
        }),
      )
      started.data
    }
  }
}

/// Runs the query on the pool and gives its rows. A query answered as
/// unavailable is tried again after a short wait, up to the attempts; one that
/// timed out may have run, so it is never tried again.
pub fn run(
  pool pool: pog.Connection,
  query query: fn(pog.Connection) -> Result(pog.Returned(row), pog.QueryError),
) -> Result(List(row), Failure) {
  attempt(pool:, query:, attempts: connection_attempts)
}

fn attempt(
  pool pool: pog.Connection,
  query query: fn(pog.Connection) -> Result(pog.Returned(row), pog.QueryError),
  attempts attempts: Int,
) -> Result(List(row), Failure) {
  case query(pool) {
    Ok(pog.Returned(rows:, ..)) -> Ok(rows)
    Error(pog.ConnectionUnavailable) ->
      case attempts > 1 {
        True -> {
          process.sleep(connection_wait_ms)
          attempt(pool:, query:, attempts: attempts - 1)
        }
        False -> Error(QueryFailed(pog.ConnectionUnavailable))
      }
    Error(error) -> Error(QueryFailed(error:))
  }
}
