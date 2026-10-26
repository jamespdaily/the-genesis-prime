//// Gives a game master permission to an account, or takes one away, run as
//// `gleam run -m genesis_prime/grant_permission -- <arguments>`. The database
//// is the one PGHOST, PGPORT, PGUSER, PGDATABASE and PGPASSWORD name
//// (`pool.from_environment`). Three forms:
////
//// - `first <account>` gives the account `grant` while no account holds it,
////   so a fresh database can get its first game master; it is refused after.
//// - `grant <by> <account> <permission>` and `revoke <by> <account>
////   <permission>` run the command as the account `<by>`, so the rule checks
////   that account's permissions and the use is logged. The tool does not ask
////   for a password: it is for a developer's own database.
////
//// Account names are the names `create_account` saved, in lower case. The
//// tool ends with status 0 when the request was carried out and 1 when it was
//// refused or failed, saying why.

import argv
import envoy
import genesis_prime/database/pool
import genesis_prime/game_master/command.{
  type Refusal, Allowed, FirstGrantOver, MissingPermission, Refused,
  UnknownPermission,
}
import genesis_prime/game_master/grant
import genesis_prime/game_master/permission.{type Permission}
import genesis_prime/game_master/store
import genesis_prime/login/account.{type Account}
import genesis_prime/login/account_store
import gleam/erlang/process
import gleam/io
import gleam/otp/static_supervisor
import gleam/result
import pog

/// How many times the tool tries again while the pool opens its first
/// connection, and how long it waits between tries, in milliseconds.
const connection_attempts = 100

const connection_wait_ms = 100

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// What the command line asks for.
type Request {
  /// Give the first `grant`.
  First(account: String)
  /// Run the grant command as `by`.
  Give(by: String, account: String, permission: String)
  /// Run the revoke command as `by`.
  Take(by: String, account: String, permission: String)
}

/// Why a request was not carried out.
type Failure {
  /// No connection to the database is open yet.
  DatabaseUnavailable
  /// The database failed.
  DatabaseFailed
  /// No account has the name.
  NoSuchAccount(name: String)
  /// A row of the accounts is not an account.
  BadAccountRow
  /// The rule refused the command.
  CommandRefused(Refusal)
  /// An account holds `grant` already.
  FirstGrantIsOver
}

/// Reads the command line, or says it is none of the three forms.
fn parse(arguments arguments: List(String)) -> Result(Request, Nil) {
  case arguments {
    ["first", account] -> Ok(First(account:))
    ["grant", by, account, permission] -> Ok(Give(by:, account:, permission:))
    ["revoke", by, account, permission] -> Ok(Take(by:, account:, permission:))
    _ -> Error(Nil)
  }
}

/// Runs the request and prints how it ended, or says why it could not.
pub fn main() -> Nil {
  case parse(arguments: argv.load().arguments) {
    Ok(request) -> run(request)
    Error(Nil) ->
      stop(
        "usage: gleam run -m genesis_prime/grant_permission -- first <account> | grant <by> <account> <permission> | revoke <by> <account> <permission>",
      )
  }
}

fn run(request: Request) -> Nil {
  let settings = case
    pool.from_environment(
      name: process.new_name("grant_permission_pool"),
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
    try_to_carry_out(
      connection: pool.connection(settings),
      request:,
      attempts: connection_attempts,
    )
  {
    Ok(done) -> {
      io.println(done)
      halt(0)
    }
    Error(failure) -> stop(describe(failure))
  }
}

/// Carries the request out, trying again while the pool has no connection yet.
fn try_to_carry_out(
  connection connection: pog.Connection,
  request request: Request,
  attempts attempts: Int,
) -> Result(String, Failure) {
  case carry_out(connection, request) {
    Error(DatabaseUnavailable) if attempts > 1 -> {
      process.sleep(connection_wait_ms)
      try_to_carry_out(connection:, request:, attempts: attempts - 1)
    }
    outcome -> outcome
  }
}

fn carry_out(
  connection: pog.Connection,
  request: Request,
) -> Result(String, Failure) {
  case request {
    First(account:) -> {
      use given <- result.try(find(connection, account))
      case
        store.give_first(
          connection:,
          account: given.id,
          permission: permission.Grant,
        )
      {
        Ok(Nil) -> Ok("gave " <> given.name <> " the permission grant")
        Error(store.AlreadyHeld) -> Error(FirstGrantIsOver)
        Error(store.FirstGrantFailed(error)) -> Error(store_failure(error))
      }
    }
    Give(by:, account:, permission:) ->
      use_command(
        connection:,
        by:,
        account:,
        permission_name: permission,
        command: grant.GrantPermission,
        done: "allowed: "
          <> by
          <> " gave "
          <> account
          <> " the permission "
          <> permission,
      )
    Take(by:, account:, permission:) ->
      use_command(
        connection:,
        by:,
        account:,
        permission_name: permission,
        command: grant.RevokePermission,
        done: "allowed: "
          <> by
          <> " took the permission "
          <> permission
          <> " from "
          <> account,
      )
  }
}

/// Runs a grant or revoke command as the account `by`: its permissions are
/// read, the rule decides, and the store carries the decision out and logs it.
fn use_command(
  connection connection: pog.Connection,
  by by: String,
  account account: String,
  permission_name permission_name: String,
  command command: fn(Int, Permission) -> grant.Command,
  done done: String,
) -> Result(String, Failure) {
  use actor <- result.try(find(connection, by))
  use target <- result.try(find(connection, account))
  use permissions <- result.try(
    store.permissions_of(connection:, account: actor.id)
    |> result.map_error(store_failure),
  )
  let command = command(target.id, permission.from_name(name: permission_name))
  let outcome =
    store.carry_out(
      connection:,
      used: grant.to_use(account: actor.id, command:),
      decision: grant.rule(permissions:, command:),
      apply: store.apply_grant,
    )
  case outcome {
    Ok(Allowed) -> Ok(done)
    Ok(Refused(refusal)) -> Error(CommandRefused(refusal))
    Error(error) -> Error(store_failure(error))
  }
}

fn find(connection: pog.Connection, name: String) -> Result(Account, Failure) {
  case account_store.find(connection, name) {
    Ok(Ok(found)) -> Ok(found)
    Ok(Error(Nil)) -> Error(NoSuchAccount(name:))
    Error(account_store.FindFailed(error)) -> Error(query_failure(error))
    Error(account_store.RowNotAccount) -> Error(BadAccountRow)
  }
}

fn store_failure(error: store.StoreError) -> Failure {
  case error {
    store.QueryFailed(error) -> query_failure(error)
    store.RowNotUse -> DatabaseFailed
  }
}

fn query_failure(error: pog.QueryError) -> Failure {
  case error {
    pog.ConnectionUnavailable -> DatabaseUnavailable
    pog.ConstraintViolated(..)
    | pog.PostgresqlError(..)
    | pog.UnexpectedArgumentCount(..)
    | pog.UnexpectedArgumentType(..)
    | pog.UnexpectedResultType(_)
    | pog.QueryTimeout -> DatabaseFailed
  }
}

fn describe(failure: Failure) -> String {
  case failure {
    DatabaseUnavailable -> "the database has no connection"
    DatabaseFailed -> "the database could not carry out the request"
    NoSuchAccount(name:) -> "no account is named " <> name
    BadAccountRow -> "a row of the accounts is not an account"
    FirstGrantIsOver ->
      "an account holds grant already, so the first grant is over; run grant <by> <account> grant as that account"
    CommandRefused(MissingPermission(required:)) ->
      "refused: the account does not hold "
      <> permission.to_name(permission: required)
    CommandRefused(UnknownPermission(name:)) ->
      "refused: no permission is named " <> name
    CommandRefused(FirstGrantOver(permission:)) ->
      "refused: "
      <> permission.to_name(permission:)
      <> " is held, so the first grant is over"
  }
}

fn stop(message: String) -> a {
  io.println_error(message)
  halt(1)
  panic as "halt does not return"
}
