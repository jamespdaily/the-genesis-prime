//// The game master commands that give a permission to an account and take
//// one away. Both require the `grant` permission of the account that uses
//// them, and neither gives a permission this code does not know.

import genesis_prime/game_master/command.{
  type Refusal, type Use, UnknownPermission, Use,
}
import genesis_prime/game_master/permission.{type Permission, Grant, Other}
import gleam/int
import gleam/result
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
  use Nil <- result.try(command.require(permissions:, required: Grant))
  case command {
    GrantPermission(target:, permission:) -> {
      use permission <- result.map(known(permission))
      [GivePermission(account: target, permission:)]
    }
    RevokePermission(target:, permission:) -> {
      use permission <- result.map(known(permission))
      [TakePermission(account: target, permission:)]
    }
  }
}

/// The permission when this code has one by its name, or the refusal.
fn known(permission: Permission) -> Result(Permission, Refusal) {
  case permission {
    Grant -> Ok(Grant)
    Other(name:) -> Error(UnknownPermission(name:))
  }
}

/// The use the log records for an account's use of a command: the command's
/// name, `grant` or `revoke`, and its arguments as text, written
/// `target=<account id> permission=<permission name>`.
pub fn to_use(account account: Int, command command: Command) -> Use {
  let #(name, target, permission) = case command {
    GrantPermission(target:, permission:) -> #("grant", target, permission)
    RevokePermission(target:, permission:) -> #("revoke", target, permission)
  }
  Use(
    account:,
    command: name,
    arguments: "target="
      <> int.to_string(target)
      <> " permission="
      <> permission.to_name(permission),
  )
}
