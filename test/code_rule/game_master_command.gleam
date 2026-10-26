//// The game master command rule: every command module under
//// `src/genesis_prime/game_master/` has a public `rule` function whose
//// parameter labelled `permissions` is the account's permissions, so no
//// command decides without checking them. The modules that are no command
//// are listed in `support_modules`.

import code_rule/source.{type Breach, type SourceFile}

/// The modules of `game_master` that are no command: the permission type, what
/// every command shares, the store, and the generated queries.
pub const support_modules = [
  "genesis_prime/game_master/permission",
  "genesis_prime/game_master/command",
  "genesis_prime/game_master/store",
  "genesis_prime/game_master/sql",
]

/// Each command module in the file's place that has no public `rule`, or whose
/// `rule` has no parameter labelled `permissions` of type
/// `Set(permission.Permission)`. A file outside `game_master`, and a support
/// module, is never a breach.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  todo as "the commands whose rule does not take the account's permissions"
}
