//// The game master data in Postgres: the permissions each account holds and
//// the log of every use of a command. Every function runs on the caller's
//// connection, so the caller is a worker and not a process that must stay
//// responsive. A command's effects and the row that records its use are
//// written in one transaction, so a use is never carried out without being
//// logged, nor logged as allowed without being carried out.

import genesis_prime/game_master/command.{
  type LoggedUse, type Outcome, type Refusal, type Use, Allowed, FirstGrantOver,
  LoggedUse, MissingPermission, Refused, UnknownPermission,
}
import genesis_prime/game_master/grant
import genesis_prime/game_master/permission.{type Permission}
import genesis_prime/game_master/sql
import genesis_prime/telemetry/log
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}
import pog

/// Why a read or a write failed.
pub type StoreError {
  /// The database failed.
  QueryFailed(pog.QueryError)
  /// A row of the log holds an outcome or a refusal that is none of the
  /// known ones.
  RowNotUse
}

/// Why a first grant was not made.
pub type FirstGrantError {
  /// An account holds the permission already, so the first grant is over.
  AlreadyHeld
  /// The database failed.
  FirstGrantFailed(StoreError)
}

/// The place the store's log lines are written from.
const place = "game_master"

/// The permissions an account holds; none for a new account.
pub fn permissions_of(
  connection connection: pog.Connection,
  account account: Int,
) -> Result(Set(Permission), StoreError) {
  sql.permissions_of_account(connection, account)
  |> result.map_error(QueryFailed)
  |> result.map(fn(returned) {
    returned.rows
    |> list.map(fn(row) { permission.from_name(name: row.name) })
    |> set.from_list
  })
}

/// Carries out a command's decision and records its use, in one transaction:
/// `apply` writes each effect in order when the rule allowed the command, and
/// one row of the log is written either way. After the commit it writes one
/// info line through the logging module. It gives how the use ended. When an
/// effect fails after the rule allowed the command, the transaction is rolled
/// back, so no row is written; the failure is then logged at warning, naming
/// the account, the command, its arguments and the failure, so no use goes
/// unlogged.
pub fn carry_out(
  connection connection: pog.Connection,
  used used: Use,
  decision decision: Result(List(effect), Refusal),
  apply apply: fn(pog.Connection, effect) -> Result(Nil, StoreError),
) -> Result(Outcome, StoreError) {
  let outcome = case decision {
    Ok(_) -> Allowed
    Error(refusal) -> Refused(refusal)
  }
  let written =
    pog.transaction(connection, fn(transaction) {
      use Nil <- result.try(
        list.try_each(result.unwrap(decision, or: []), fn(effect) {
          apply(transaction, effect)
        }),
      )
      record_use(connection: transaction, used:, outcome:)
    })
  let who = who_of(Some(used.account))
  let description = used.command <> " " <> used.arguments
  case written {
    Ok(Nil) -> {
      log.info(
        who:,
        text: "game master command "
          <> description
          <> " "
          <> describe_outcome(outcome),
      )
      Ok(outcome)
    }
    Error(failure) -> {
      let error = store_error(failure)
      log.warning(
        who:,
        text: "game master command "
          <> description
          <> " failed: "
          <> describe_error(error),
      )
      Error(error)
    }
  }
}

/// Writes one effect of a grant or revoke command: the permission row.
pub fn apply_grant(
  connection connection: pog.Connection,
  effect effect: grant.Effect,
) -> Result(Nil, StoreError) {
  case effect {
    grant.GivePermission(account:, permission:) ->
      sql.give_permission(connection, account, permission.to_name(permission:))
      |> written
    grant.TakePermission(account:, permission:) ->
      sql.take_permission(connection, account, permission.to_name(permission:))
      |> written
  }
}

/// Gives an account a permission when no account holds it yet. No account
/// uses a command to do it, so a database that has no game master can get its
/// first. The permission row and the row of the log (command `first_grant`,
/// no acting account, the arguments written `account=<account id>
/// permission=<permission name>`) are written in one transaction, and one
/// info line is written through the logging module. A first grant after an
/// account holds the permission writes no permission row but is logged as
/// refused (`FirstGrantOver`) and gives `AlreadyHeld`.
pub fn give_first(
  connection connection: pog.Connection,
  account account: Int,
  permission permission: Permission,
) -> Result(Nil, FirstGrantError) {
  let name = permission.to_name(permission:)
  let arguments = "account=" <> int.to_string(account) <> " permission=" <> name
  let written =
    pog.transaction(connection, fn(transaction) {
      use _ <- result.try(
        sql.lock_first_grant(transaction, name)
        |> result.map_error(QueryFailed),
      )
      use given <- result.try(
        sql.give_first_permission(transaction, account, name)
        |> result.map_error(QueryFailed),
      )
      case given.rows {
        [_, ..] ->
          sql.record_first_grant(transaction, arguments)
          |> written
          |> result.replace(Allowed)
        [] ->
          sql.record_refused_first_grant(transaction, arguments, name)
          |> written
          |> result.replace(Refused(FirstGrantOver(permission:)))
      }
    })
  let who = who_of(None)
  let description = "first_grant " <> arguments
  case written {
    Ok(outcome) -> {
      log.info(
        who:,
        text: "game master command "
          <> description
          <> " "
          <> describe_outcome(outcome),
      )
      case outcome {
        Allowed -> Ok(Nil)
        Refused(_) -> Error(AlreadyHeld)
      }
    }
    Error(failure) -> {
      let error = store_error(failure)
      log.warning(
        who:,
        text: "game master command "
          <> description
          <> " failed: "
          <> describe_error(error),
      )
      Error(FirstGrantFailed(error))
    }
  }
}

/// Every use of a command by an account, oldest first.
pub fn uses_of(
  connection connection: pog.Connection,
  account account: Int,
) -> Result(List(LoggedUse), StoreError) {
  use returned <- result.try(
    sql.uses_of_account(connection, account) |> result.map_error(QueryFailed),
  )
  list.try_map(returned.rows, fn(row) {
    logged_use(
      actor: Some(row.account_id),
      command: row.command,
      arguments: row.arguments,
      outcome: row.outcome,
      refusal: row.refusal,
      refusal_permission: row.refusal_permission,
    )
  })
}

/// Every use made by the database's operator and not by an account, oldest
/// first: the first grants, allowed and refused.
pub fn operator_uses(
  connection connection: pog.Connection,
) -> Result(List(LoggedUse), StoreError) {
  use returned <- result.try(
    sql.operator_uses(connection) |> result.map_error(QueryFailed),
  )
  list.try_map(returned.rows, fn(row) {
    logged_use(
      actor: None,
      command: row.command,
      arguments: row.arguments,
      outcome: row.outcome,
      refusal: row.refusal,
      refusal_permission: row.refusal_permission,
    )
  })
}

/// Writes the row of the log for a use by an account.
fn record_use(
  connection connection: pog.Connection,
  used used: Use,
  outcome outcome: Outcome,
) -> Result(Nil, StoreError) {
  case outcome {
    Allowed ->
      sql.record_allowed_use(
        connection,
        used.account,
        used.command,
        used.arguments,
      )
      |> written
    Refused(refusal) -> {
      let #(kind, name) = refusal_columns(refusal)
      sql.record_refused_use(
        connection,
        used.account,
        used.command,
        used.arguments,
        kind,
        name,
      )
      |> written
    }
  }
}

/// A query that returns no rows of interest: its error as the store's.
fn written(
  outcome: Result(pog.Returned(a), pog.QueryError),
) -> Result(Nil, StoreError) {
  outcome |> result.replace(Nil) |> result.map_error(QueryFailed)
}

/// The two columns a refusal is saved in: why, and the permission's name.
fn refusal_columns(refusal: Refusal) -> #(String, String) {
  case refusal {
    MissingPermission(required:) -> #(
      "missing_permission",
      permission.to_name(permission: required),
    )
    UnknownPermission(name:) -> #("unknown_permission", name)
    FirstGrantOver(permission:) -> #(
      "first_grant_over",
      permission.to_name(permission:),
    )
  }
}

/// A row of the log as the use it holds, or `RowNotUse` when its outcome or
/// refusal is none of the known ones.
fn logged_use(
  actor actor: Option(Int),
  command command: String,
  arguments arguments: String,
  outcome outcome: String,
  refusal refusal: Option(String),
  refusal_permission refusal_permission: Option(String),
) -> Result(LoggedUse, StoreError) {
  let outcome = case outcome, refusal, refusal_permission {
    "allowed", None, None -> Ok(Allowed)
    "refused", Some("missing_permission"), Some(name) ->
      Ok(Refused(MissingPermission(required: permission.from_name(name:))))
    "refused", Some("unknown_permission"), Some(name) ->
      Ok(Refused(UnknownPermission(name:)))
    "refused", Some("first_grant_over"), Some(name) ->
      Ok(Refused(FirstGrantOver(permission: permission.from_name(name:))))
    _, _, _ -> Error(RowNotUse)
  }
  result.map(outcome, fn(outcome) {
    LoggedUse(actor:, command:, arguments:, outcome:)
  })
}

fn store_error(failure: pog.TransactionError(StoreError)) -> StoreError {
  case failure {
    pog.TransactionQueryError(error) -> QueryFailed(error)
    pog.TransactionRolledBack(error) -> error
  }
}

/// The metadata of a line about a use: the account, when there is one, and
/// where the line is written from.
fn who_of(account: Option(Int)) -> log.Who {
  log.Who(..log.nobody, account:, place: Some(log.Process(place)))
}

fn describe_outcome(outcome: Outcome) -> String {
  case outcome {
    Allowed -> "allowed"
    Refused(refusal) -> {
      let #(kind, name) = refusal_columns(refusal)
      "refused: " <> kind <> " " <> name
    }
  }
}

fn describe_error(error: StoreError) -> String {
  case error {
    RowNotUse -> "a row of the log is not a use"
    QueryFailed(pog.ConstraintViolated(constraint:, ..)) ->
      "the database refused the change: constraint " <> constraint
    QueryFailed(pog.PostgresqlError(name:, ..)) -> "postgresql error " <> name
    QueryFailed(pog.QueryTimeout) -> "the query timed out"
    QueryFailed(pog.ConnectionUnavailable) -> "no database connection"
    QueryFailed(pog.UnexpectedArgumentCount(..))
    | QueryFailed(pog.UnexpectedArgumentType(..))
    | QueryFailed(pog.UnexpectedResultType(_)) ->
      "the query and its arguments or rows do not match"
  }
}
