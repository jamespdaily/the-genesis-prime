//// What every game master command shares. A command's rule is a pure
//// function that takes the permissions of the account that used it and the
//// command, and returns the effects to carry out or the refusal; it checks
//// the permission first, through `require`, before it decides anything else.
//// The store carries the effects out and records the use, allowed or
//// refused (`game_master/store`).

import genesis_prime/game_master/permission.{type Permission}
import gleam/set.{type Set}

/// Why a rule refused a command.
pub type Refusal {
  /// The account does not hold the permission the command requires.
  MissingPermission(required: Permission)
  /// The command names a permission this code has none for, by its name.
  UnknownPermission(name: String)
}

/// How a use of a command ended.
pub type Outcome {
  Allowed
  Refused(Refusal)
}

/// One use of a command as the log holds it: the account that used it, the
/// command's name, and what the command was given, as text.
pub type Use {
  Use(account: Int, command: String, arguments: String)
}

/// A use read back from the log, with how it ended.
pub type LoggedUse {
  LoggedUse(used: Use, outcome: Outcome)
}

/// Whether an account's permissions hold the one a command requires: `Ok`, or
/// the refusal. Every rule calls this before anything else.
pub fn require(
  permissions permissions: Set(Permission),
  required required: Permission,
) -> Result(Nil, Refusal) {
  todo as "Ok when the set holds the permission, MissingPermission otherwise"
}
