//// Adds an account a client can log in with: the login name in lower case, as
//// the client sends it, a fresh 32-byte salt, the SRP verifier of the name
//// and password (genesis_prime/login/srp), and a fresh game account GUID. The
//// password is never kept.
////
//// `gleam run -m genesis_prime/add_account -- <login name> <password>`
////
//// The database is the one the server uses, from PGHOST, PGPORT, PGUSER,
//// PGPASSWORD and PGDATABASE. A login name already taken, and an empty one, are
//// refused with the constraint that refused them
//// (`account_login_name_is_unique`, `account_login_name_is_not_empty`).

import argv
import genesis_prime/add_account/sql
import genesis_prime/dev_database
import genesis_prime/login/guid
import genesis_prime/login/srp
import gleam/crypto
import gleam/int
import gleam/result
import gleam/string
import pog

/// Why the account was not added.
type Failure {
  WrongArguments
  Database(failure: dev_database.Failure)
}

pub fn main() -> Nil {
  dev_database.finish(result: add(), describe:)
}

fn add() -> Result(String, Failure) {
  case argv.load().arguments {
    [login_name, password] ->
      insert(login_name: string.lowercase(login_name), password:)
    _ -> Error(WrongArguments)
  }
}

/// What an account is made with: a fresh 32-byte salt, the SRP verifier of the
/// lower-case name and the password, and the text of a fresh game account GUID.
/// Other tools that add accounts insert it themselves.
pub type Credentials {
  Credentials(salt: BitArray, verifier: BitArray, game_account_id: String)
}

/// Fresh credentials for the login name and password.
pub fn credentials(
  login_name login_name: String,
  password password: String,
) -> Credentials {
  let salt = crypto.strong_random_bytes(32)
  let verifier = srp.verifier(name: login_name, password:, salt:)
  let assert Ok(game_account_id) =
    guid.from_wire(crypto.strong_random_bytes(16))
    as "sixteen bytes are a GUID"
  Credentials(salt:, verifier:, game_account_id: guid.to_text(game_account_id))
}

/// The query that adds an account, and the text of its game account's GUID, with
/// fresh credentials. Other tools that add accounts run it on their own
/// connection.
pub fn new_account(
  login_name login_name: String,
  password password: String,
) -> #(
  String,
  fn(pog.Connection) ->
    Result(pog.Returned(sql.InsertAccountRow), pog.QueryError),
) {
  let Credentials(salt:, verifier:, game_account_id:) =
    credentials(login_name:, password:)
  #(game_account_id, sql.insert_account(
    _,
    login_name,
    salt,
    verifier,
    game_account_id,
  ))
}

fn insert(
  login_name login_name: String,
  password password: String,
) -> Result(String, Failure) {
  let #(game_account_id, query) = new_account(login_name:, password:)
  use rows <- result.try(
    dev_database.run(query)
    |> result.map_error(Database),
  )
  case rows {
    [sql.InsertAccountRow(account_id:)] ->
      Ok(
        "added the account "
        <> login_name
        <> " with the id "
        <> int.to_string(account_id)
        <> " and the game account "
        <> game_account_id,
      )
    _ -> Error(Database(dev_database.NotChanged("the database returned no id")))
  }
}

fn describe(failure: Failure) -> String {
  case failure {
    WrongArguments ->
      "usage: gleam run -m genesis_prime/add_account -- <login name> <password>"
    Database(failure:) ->
      dev_database.describe(failure:, change: "add the account")
  }
}
