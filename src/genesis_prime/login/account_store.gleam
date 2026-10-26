//// The accounts in Postgres: adding one, and finding one by its name. The
//// password is turned into its SRP salt and verifier here, once, and never
//// saved (`srp.verifier`).

import genesis_prime/login/account.{type Account}
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

/// Adds an account with the lower-case name, a new random salt and the
/// verifier of the password, and gives it with the GUID the database chose.
pub fn create(
  connection connection: pog.Connection,
  name name: String,
  password password: String,
) -> Result(Account, CreateError) {
  todo as "add an account"
}

/// The account of a name, in lower case, or none.
pub fn find(
  connection connection: pog.Connection,
  name name: String,
) -> Result(Result(Account, Nil), FindError) {
  todo as "find an account"
}
