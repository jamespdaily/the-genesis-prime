//// Adds an account to the database, run as
//// `gleam run -m genesis_prime/create_account -- <name> <password>`. The
//// database is the one PGHOST, PGPORT, PGUSER, PGDATABASE and PGPASSWORD name
//// (`pool.from_environment`). The name is saved in lower case, as the client
//// sends it, and only the password's SRP salt and verifier are saved. The
//// password is on the command line, so the tool is for test accounts.

import argv
import envoy
import genesis_prime/database/pool
import genesis_prime/login/account
import genesis_prime/login/account_store.{type CreateError}
import genesis_prime/login/guid
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/otp/static_supervisor
import pog

/// How many times the tool tries again while the pool opens its first
/// connection, and how long it waits between tries, in milliseconds.
const connection_attempts = 100

const connection_wait_ms = 100

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Creates the account and prints its UserId, or says why it could not.
pub fn main() -> Nil {
  case argv.load().arguments {
    [name, password] -> create(name, password)
    _ ->
      stop(
        "usage: gleam run -m genesis_prime/create_account -- <name> <password>",
      )
  }
}

fn create(name: String, password: String) -> Nil {
  let settings = case
    pool.from_environment(
      name: process.new_name("create_account_pool"),
      get: envoy.get,
    )
  {
    Ok(settings) -> settings
    Error(error) -> stop(pool.describe(error))
  }
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(pool.supervised(settings))
    |> static_supervisor.start
    as "the database pool did not start"
  case
    try_to_create(
      connection: pool.connection(settings),
      name:,
      password:,
      attempts: connection_attempts,
    )
  {
    Ok(created) -> {
      io.println(
        "created "
        <> created.name
        <> " with UserId "
        <> guid.to_text(created.user_id),
      )
      halt(0)
    }
    Error(error) -> stop(describe(error))
  }
}

/// Creates the account, trying again while the pool has no connection yet.
fn try_to_create(
  connection connection: pog.Connection,
  name name: String,
  password password: String,
  attempts attempts: Int,
) -> Result(account.Account, CreateError) {
  case account_store.create(connection, name, password) {
    Error(account_store.CreateFailed(pog.ConnectionUnavailable))
      if attempts > 1
    -> {
      process.sleep(connection_wait_ms)
      try_to_create(connection:, name:, password:, attempts: attempts - 1)
    }
    outcome -> outcome
  }
}

fn describe(error: CreateError) -> String {
  case error {
    account_store.BadName(account.NameEmpty) -> "the name is empty"
    account_store.BadName(account.NameTooLong(units:)) ->
      "the name has "
      <> int.to_string(units)
      <> " UTF-16 units; the most is 250"
    account_store.NameTaken -> "an account of that name exists"
    account_store.CreateFailed(_) -> "the database could not add the account"
  }
}

fn stop(message: String) -> a {
  io.println_error(message)
  halt(1)
  panic as "halt does not return"
}
