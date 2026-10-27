//// Adds an account a client can log in with: the login name in lower case, as
//// the client sends it, a fresh 32-byte salt, the SRP verifier of the name
//// and password (genesis_prime/login/srp), and a fresh game account GUID. The
//// password is never kept.
////
//// `gleam run -m genesis_prime/add_account -- <login name> <password>`
////
//// The database is the one the server uses, from PGHOST, PGPORT, PGUSER,
//// PGPASSWORD and PGDATABASE. A login name already taken is refused with the
//// constraint that refused it.

import argv
import genesis_prime
import genesis_prime/add_account/sql
import genesis_prime/login/guid
import genesis_prime/login/srp
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/string
import pog

/// Why the account was not added.
type Failure {
  WrongArguments
  EmptyLoginName
  DatabaseDown
  Refused(constraint: String)
  NotInserted(reason: String)
}

pub fn main() -> Nil {
  case add() {
    Ok(account_id) -> io.println("added the account " <> account_id)
    Error(failure) -> {
      io.println_error(describe(failure))
      halt(1)
    }
  }
}

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

fn add() -> Result(String, Failure) {
  case argv.load().arguments {
    [login_name, password] ->
      case string.lowercase(login_name) {
        "" -> Error(EmptyLoginName)
        login_name -> insert(login_name:, password:)
      }
    _ -> Error(WrongArguments)
  }
}

fn insert(
  login_name login_name: String,
  password password: String,
) -> Result(String, Failure) {
  let salt = crypto.strong_random_bytes(32)
  let verifier = srp.verifier(name: login_name, password:, salt:)
  let assert Ok(game_account_id) =
    guid.from_wire(crypto.strong_random_bytes(16))
    as "sixteen bytes are a GUID"
  case pog.start(genesis_prime.pool()) {
    Error(_) -> Error(DatabaseDown)
    Ok(started) ->
      insert_when_connected(
        pool: started.data,
        login_name:,
        salt:,
        verifier:,
        game_account_id: guid.to_text(game_account_id),
        attempts: connection_attempts,
      )
  }
}

/// How many times the query is tried while the pool has no connection yet: it
/// opens its connections after it starts, and a query made before one is open
/// is answered as unavailable.
const connection_attempts = 5

/// How long to wait before trying again, in milliseconds.
const connection_wait_ms = 100

fn insert_when_connected(
  pool pool: pog.Connection,
  login_name login_name: String,
  salt salt: BitArray,
  verifier verifier: BitArray,
  game_account_id game_account_id: String,
  attempts attempts: Int,
) -> Result(String, Failure) {
  case sql.insert_account(pool, login_name, salt, verifier, game_account_id) {
    Ok(pog.Returned(rows: [sql.InsertAccountRow(account_id:)], ..)) ->
      Ok(
        login_name
        <> " with the id "
        <> int.to_string(account_id)
        <> " and the game account "
        <> game_account_id,
      )
    Ok(pog.Returned(..)) -> Error(NotInserted("the database returned no id"))
    Error(pog.ConstraintViolated(constraint:, ..)) ->
      Error(Refused(constraint:))
    Error(pog.ConnectionUnavailable) | Error(pog.QueryTimeout) ->
      case attempts > 1 {
        True -> {
          process.sleep(connection_wait_ms)
          insert_when_connected(
            pool:,
            login_name:,
            salt:,
            verifier:,
            game_account_id:,
            attempts: attempts - 1,
          )
        }
        False -> Error(DatabaseDown)
      }
    Error(pog.PostgresqlError(name:, message:, ..)) ->
      Error(NotInserted(name <> ": " <> message))
    Error(pog.UnexpectedArgumentCount(..))
    | Error(pog.UnexpectedArgumentType(..))
    | Error(pog.UnexpectedResultType(..)) ->
      Error(NotInserted("the query and the table do not match"))
  }
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/add_account -- <login name> <password>"
    EmptyLoginName -> "the login name is empty"
    DatabaseDown ->
      "the database could not be reached: check PGHOST, PGPORT, PGUSER, PGPASSWORD and PGDATABASE"
    Refused(constraint:) -> "the database refused the account: " <> constraint
    NotInserted(reason:) -> "the account was not added: " <> reason
  }
}
