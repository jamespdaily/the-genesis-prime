//// The accounts in Postgres: each test has a database of its own made from
//// the migrated template (`template_database`). Expected values come from the
//// accounts table in `priv/migrations/0001_account.sql` (the name is unique,
//// the GUID is the database's) and from SRP: the saved salt and verifier are
//// the ones `srp.verifier` makes, a password is never saved, and two accounts
//// with one password have different salts (StsConnLib64.MT.dll!0x18002ccd0 and
//// 0x18002d4e0: x is the hash of the salt and the password's hash).

import genesis_prime/login/account
import genesis_prime/login/account_store.{BadName, NameTaken}
import genesis_prime/login/guid
import genesis_prime/login/srp
import gleam/bit_array
import gleam/string
import owned_test
import template_database

pub fn a_new_account_is_found_by_its_lower_case_name_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(created) =
    account_store.create(database.connection, "Jim", "secret")
    as "the account is created"
  assert created.name == "jim"
    as "StartStsLogin 0x1400b4500: the client lower-cases the name it sends, so the account is kept under it"
  assert account_store.find(database.connection, "jim") == Ok(Ok(created))
    as "an account saved is found by its name, whole"
}

pub fn the_saved_salt_and_verifier_are_the_srp_values_of_the_password_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(created) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  assert bit_array.byte_size(created.salt) == 16
    as "the salt is as long as the vector's (vector.StsConnLib64.MT.dll!0x18002d4e0.srp: 16 bytes)"
  assert created.verifier
    == srp.verifier(name: "jim", password: "secret", salt: created.salt)
    as "StsConnLib64.MT.dll!0x18002d4e0: v = g^x mod N with x from the salt and the password"
}

pub fn an_account_holds_its_guid_and_a_creation_time_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(created) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  assert guid.to_text(created.user_id) |> string.length == 36
    as "opcode.0x592: the UserId is a GUID, written 8-4-4-4-12"
  assert string.length(created.created) == 20
    && string.ends_with(created.created, "Z")
    as "the creation time is RFC 3339 in UTC to the second, as 2026-01-02T03:04:05Z"
}

pub fn two_accounts_with_one_password_have_different_salts_verifiers_and_guids_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(first) =
    account_store.create(database.connection, "jim", "secret")
    as "the first account is created"
  let assert Ok(second) =
    account_store.create(database.connection, "sam", "secret")
    as "the second account is created"
  assert first.salt != second.salt
    as "SRP: a salt per account, so equal passwords do not give equal verifiers"
  assert first.verifier != second.verifier as "SRP: the verifier holds the salt"
  assert first.user_id != second.user_id
    as "the UserId names one account (user_id is unique in the table)"
}

pub fn a_name_that_is_taken_is_refused_whatever_its_case_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(_) = account_store.create(database.connection, "jim", "secret")
    as "the first account is created"
  assert account_store.create(database.connection, "JIM", "other")
    == Error(NameTaken)
    as "priv/migrations/0001_account.sql: the name is the primary key, and the name the client sends is lower case"
}

pub fn a_name_that_cannot_name_an_account_is_refused_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  assert account_store.create(database.connection, "", "secret")
    == Error(BadName(account.NameEmpty))
    as "StsConnLib64.MT.dll!0x180006fb0: without a name the request is not sent"
  assert account_store.create(
      database.connection,
      string.repeat("a", 251),
      "secret",
    )
    == Error(BadName(account.NameTooLong(251)))
    as "opcode.0x592: an account name over 250 characters"
}

pub fn an_account_that_does_not_exist_is_not_found_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  assert account_store.find(database.connection, "nobody") == Ok(Error(Nil))
    as "an absent account is not a failure of the database"
}

pub fn a_name_is_found_whatever_its_case_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  let assert Ok(created) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  assert account_store.find(database.connection, "JIM") == Ok(Ok(created))
    as "the accounts are kept under the lower-case name the client sends"
}
