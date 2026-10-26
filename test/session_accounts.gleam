//// Puts the accounts a recorded session used into a fresh database, as the
//// recording server found them: with the salt, the verifier and the user id
//// the recording holds, which `account_store.create` would draw anew. It is
//// test-only SQL; the server has no way to make an account with a chosen
//// salt.

import genesis_prime/recording/session.{type UsedAccount}
import pog

/// Inserts the account row; the database gives it its own number.
pub fn insert(
  connection _connection: pog.Connection,
  account _account: UsedAccount,
) -> Nil {
  panic as "shape only: built after the tests"
}
