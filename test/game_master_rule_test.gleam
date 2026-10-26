//// The pure game master rules (test 2 of the step's list, and the names of
//// permissions). No client evidence exists for game master commands; the
//// expected values are the issue's rules and the approved list: a new account
//// holds no permission, a command's rule checks the account's permissions
//// first and gives a refusal and no effect when the permission is missing,
//// granting and revoking each need the `grant` permission, and a permission
//// name the code does not know is kept as `Other(name)` and given to no one.

import genesis_prime/game_master/command.{
  MissingPermission, UnknownPermission, Use,
}
import genesis_prime/game_master/grant.{
  GivePermission, GrantPermission, RevokePermission, TakePermission,
}
import genesis_prime/game_master/permission.{Grant, Other}
import gleam/set
import owned_test

/// An arbitrary account id for the account a command is about.
const target = 2

/// An arbitrary account id for the account that uses a command.
const actor = 1

pub fn a_permission_is_saved_under_its_name_and_a_name_the_code_does_not_know_is_kept_test() -> Nil {
  use <- owned_test.run(5000)
  assert permission.to_name(permission: Grant) == "grant"
    as "the issue: the permission that gives permissions is named `grant`"
  assert permission.from_name(name: "grant") == Grant
    as "a saved name is read back as its permission"
  assert permission.from_name(name: "teleport") == Other("teleport")
    as "the issue: a name read that the code does not know is Other(name), not lost"
  assert permission.to_name(permission: Other("teleport")) == "teleport"
    as "an unknown name is written back as it was read"
}

pub fn a_rule_that_requires_a_permission_refuses_an_account_that_lacks_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert command.require(permissions: set.new(), required: Grant)
    == Error(MissingPermission(required: Grant))
    as "the issue: a new account holds no permission, so the check fails"
  assert command.require(
      permissions: set.from_list([Other("teleport")]),
      required: Grant,
    )
    == Error(MissingPermission(required: Grant))
    as "named permissions grant exactly what is listed: another permission does not stand for `grant`"
  assert command.require(permissions: set.from_list([Grant]), required: Grant)
    == Ok(Nil)
    as "an account that holds the permission passes the check"
}

pub fn a_grant_or_revoke_by_an_account_without_grant_is_refused_with_no_effect_test() -> Nil {
  use <- owned_test.run(5000)
  let nothing = set.new()
  assert grant.rule(
      permissions: nothing,
      command: GrantPermission(target:, permission: Grant),
    )
    == Error(MissingPermission(required: Grant))
    as "test 2: the rule checks first; without the permission it gives a refusal and no effect"
  assert grant.rule(
      permissions: nothing,
      command: RevokePermission(target:, permission: Grant),
    )
    == Error(MissingPermission(required: Grant))
    as "test 2: revoking needs `grant` as granting does"
}

pub fn a_grant_or_revoke_by_an_account_with_grant_gives_its_effect_test() -> Nil {
  use <- owned_test.run(5000)
  let holder = set.from_list([Grant])
  assert grant.rule(
      permissions: holder,
      command: GrantPermission(target:, permission: Grant),
    )
    == Ok([GivePermission(account: target, permission: Grant)])
    as "test 2: with the permission, a grant has the effect of giving the permission to the target"
  assert grant.rule(
      permissions: holder,
      command: RevokePermission(target:, permission: Grant),
    )
    == Ok([TakePermission(account: target, permission: Grant)])
    as "test 2: with the permission, a revoke has the effect of taking it from the target"
}

pub fn the_permission_is_checked_before_the_permission_named_is_test() -> Nil {
  use <- owned_test.run(5000)
  let unknown = Other("teleport")
  assert grant.rule(
      permissions: set.new(),
      command: GrantPermission(target:, permission: unknown),
    )
    == Error(MissingPermission(required: Grant))
    as "the rule checks first: an account without `grant` is refused for that, not for the name it typed"
  assert grant.rule(
      permissions: set.from_list([Grant]),
      command: GrantPermission(target:, permission: unknown),
    )
    == Error(UnknownPermission(name: "teleport"))
    as "a name the code has no permission for is given to no one"
  assert grant.rule(
      permissions: set.from_list([Grant]),
      command: RevokePermission(target:, permission: unknown),
    )
    == Error(UnknownPermission(name: "teleport"))
    as "a revoke of an unknown name is refused the same way"
}

pub fn a_use_is_logged_under_its_command_name_and_arguments_as_text_test() -> Nil {
  use <- owned_test.run(5000)
  assert grant.to_use(
      account: actor,
      command: GrantPermission(target:, permission: Grant),
    )
    == Use(
      account: actor,
      command: "grant",
      arguments: "target=2 permission=grant",
    )
    as "test 4: the log holds the account, the command and its arguments; `grant` and `revoke` are the commands' names"
  assert grant.to_use(
      account: actor,
      command: RevokePermission(target:, permission: Other("teleport")),
    )
    == Use(
      account: actor,
      command: "revoke",
      arguments: "target=2 permission=teleport",
    )
    as "an unknown permission is logged under the name that was typed"
}
