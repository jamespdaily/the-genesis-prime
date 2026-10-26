//// The game master data in Postgres: the permissions each account holds and
//// the log of every use of a command. Every function runs on the caller's
//// connection, so the caller is a worker and not a process that must stay
//// responsive. A command's effects and the row that records its use are
//// written in one transaction, so a use is never carried out without being
//// logged, nor logged as allowed without being carried out.

import genesis_prime/game_master/command.{
  type LoggedUse, type Outcome, type Refusal, type Use,
}
import genesis_prime/game_master/grant
import genesis_prime/game_master/permission.{type Permission}
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

/// The permissions an account holds; none for a new account.
pub fn permissions_of(
  connection connection: pog.Connection,
  account account: Int,
) -> Result(Set(Permission), StoreError) {
  todo as "read the account's permission rows into permissions"
}

/// Carries out a command's decision and records its use, in one transaction:
/// `apply` writes each effect in order when the rule allowed the command, and
/// one row of the log is written either way. After the commit it writes one
/// info line through the logging module. It gives how the use ended.
pub fn carry_out(
  connection connection: pog.Connection,
  used used: Use,
  decision decision: Result(List(effect), Refusal),
  apply apply: fn(pog.Connection, effect) -> Result(Nil, StoreError),
) -> Result(Outcome, StoreError) {
  todo as "apply the effects, write the log row, then log the use"
}

/// Writes one effect of a grant or revoke command: the permission row.
pub fn apply_grant(
  connection connection: pog.Connection,
  effect effect: grant.Effect,
) -> Result(Nil, StoreError) {
  todo as "insert or delete the permission row"
}

/// Gives an account a permission when no account holds it yet. No account
/// uses a command to do it, so a database that has no game master can get its
/// first. It writes the permission row only.
pub fn give_first(
  connection connection: pog.Connection,
  account account: Int,
  permission permission: Permission,
) -> Result(Nil, FirstGrantError) {
  todo as "insert the row only while no account holds the permission"
}

/// Every use of a command by an account, oldest first.
pub fn uses_of(
  connection connection: pog.Connection,
  account account: Int,
) -> Result(List(LoggedUse), StoreError) {
  todo as "read the account's log rows into logged uses"
}
