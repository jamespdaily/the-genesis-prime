//// The game master commands that give a permission to an account and take
//// one away. Both require the `grant` permission of the account that uses
//// them, and neither gives a permission this code does not know.

import genesis_prime/game_master/command.{type Refusal, type Use}
import genesis_prime/game_master/permission.{type Permission}
import gleam/set.{type Set}

/// A use of one of the commands: the account it is about, by its id, and the
/// permission.
pub type Command {
  GrantPermission(target: Int, permission: Permission)
  RevokePermission(target: Int, permission: Permission)
}

/// What a command that was allowed has the store do.
pub type Effect {
  GivePermission(account: Int, permission: Permission)
  TakePermission(account: Int, permission: Permission)
}

/// The effects of a command used by an account that holds `permissions`, or
/// the refusal. The account's permissions are checked first, then the
/// permission named.
pub fn rule(
  permissions permissions: Set(Permission),
  command command: Command,
) -> Result(List(Effect), Refusal) {
  todo as "require Grant, then refuse an Other permission, then the effect"
}

/// The use the log records for an account's use of a command: the command's
/// name, `grant` or `revoke`, and its arguments as text, written
/// `target=<account id> permission=<permission name>`.
pub fn to_use(account account: Int, command command: Command) -> Use {
  todo as "the use of the command with the arguments written as text"
}
