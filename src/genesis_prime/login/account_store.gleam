//// The accounts in Postgres: adding one, and finding one by its name. The
//// password is turned into its SRP salt and verifier here, once, and never
//// saved (`srp.verifier`).

import genesis_prime/login/account.{type Account, Account}
import genesis_prime/login/guid
import genesis_prime/login/sql
import genesis_prime/login/srp
import gleam/crypto
import gleam/result
import pog

/// Why an account was not added.
pub type CreateError {
  /// The name cannot name an account.
  BadName(account.NameError)
  /// An account of that name exists.
  NameTaken
  /// The database failed.
  CreateFailed(pog.QueryError)
}

/// Why an account was not found for a reason other than being absent.
pub type FindError {
  /// The database failed.
  FindFailed(pog.QueryError)
  /// The row holds a GUID that is not one.
  RowNotAccount
}

/// How many random bytes make a salt: the vector's salt is 16
/// (vector.StsConnLib64.MT.dll!0x18002d4e0.srp).
const salt_bytes = 16

/// Adds an account with the lower-case name, a new random salt and the
/// verifier of the password, and gives it with the GUID the database chose.
pub fn create(
  connection connection: pog.Connection,
  name name: String,
  password password: String,
) -> Result(Account, CreateError) {
  use name <- result.try(
    account.lower_case_name(name) |> result.map_error(BadName),
  )
  let salt = crypto.strong_random_bytes(salt_bytes)
  let verifier = srp.verifier(name:, password:, salt:)
  case sql.create_account(connection, name, salt, verifier) {
    Ok(pog.Returned(rows: [row], ..)) ->
      case guid.from_text(row.user_id) {
        Ok(user_id) ->
          Ok(Account(
            id: row.id,
            name:,
            user_id:,
            salt:,
            verifier:,
            created: row.created,
          ))
        Error(guid.NotSixteenBytes(_)) | Error(guid.NotGuidText(_)) ->
          panic as "the database gave an account a user_id that is not a GUID"
      }
    Ok(pog.Returned(..)) -> panic as "an insert of one account returns one row"
    Error(pog.ConstraintViolated(..)) -> Error(NameTaken)
    Error(error) -> Error(CreateFailed(error))
  }
}

/// The account of a name, in lower case, or none.
pub fn find(
  connection connection: pog.Connection,
  name name: String,
) -> Result(Result(Account, Nil), FindError) {
  case account.lower_case_name(name) {
    Error(account.NameEmpty) | Error(account.NameTooLong(_)) -> Ok(Error(Nil))
    Ok(name) ->
      case sql.find_account(connection, name) {
        Ok(pog.Returned(rows: [], ..)) -> Ok(Error(Nil))
        Ok(pog.Returned(rows: [row, ..], ..)) ->
          case guid.from_text(row.user_id) {
            Ok(user_id) ->
              Ok(
                Ok(Account(
                  id: row.id,
                  name: row.name,
                  user_id:,
                  salt: row.salt,
                  verifier: row.verifier,
                  created: row.created,
                )),
              )
            Error(guid.NotSixteenBytes(_)) | Error(guid.NotGuidText(_)) ->
              Error(RowNotAccount)
          }
        Error(error) -> Error(FindFailed(error))
      }
  }
}
