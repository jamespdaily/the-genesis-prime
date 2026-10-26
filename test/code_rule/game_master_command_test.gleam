//// The game master command rule (test 4 of the step's list). The expected
//// value is CLAUDE.md, Every change: a game master command checks the
//// account's permission in its rule before it acts. So every command module
//// under `src/genesis_prime/game_master/` has a public `rule` function with a
//// parameter labelled `permissions` of type `Set(Permission)`; a module
//// without one, or with one that does not take the permissions, is a breach
//// at the line of its `rule` (line 1 when it has none). The modules that are
//// no command (`support_modules`) and files outside `game_master` are never a
//// breach. Each breach is planted in a made-up file, each clean case beside
//// it, and the rule is then run over the real tree.

import code_rule/game_master_command
import code_rule/planted
import code_rule/repository
import gleam/list
import owned_test

const imports = [
  "import genesis_prime/game_master/command.{type Refusal}",
  "import genesis_prime/game_master/permission.{type Permission}",
  "import gleam/set.{type Set}",
  "",
]

fn command_module(path path: String, rule rule: List(String)) -> List(Int) {
  planted.file(path, list.append(["//// A planted module.", ..imports], rule))
  |> game_master_command.breaches
  |> planted.lines
}

pub fn a_rule_that_takes_the_permissions_is_clean_test() -> Nil {
  use <- owned_test.run(5000)
  assert command_module(
      path: "src/genesis_prime/game_master/teleport.gleam",
      rule: [
        "pub fn rule(",
        "  permissions permissions: Set(Permission),",
        "  destination destination: Int,",
        ") -> Result(List(Int), Refusal) {",
        "  Ok([destination])",
        "}",
      ],
    )
    == []
}

pub fn a_rule_that_does_not_take_the_permissions_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  assert command_module(
      path: "src/genesis_prime/game_master/teleport.gleam",
      rule: [
        "pub fn rule(destination destination: Int) -> Result(List(Int), Refusal) {",
        "  Ok([destination])",
        "}",
      ],
    )
    == [6]
    as "CLAUDE.md: a command's rule checks the account's permission, so it must be given them"
}

pub fn a_rule_whose_permissions_are_not_a_set_of_permission_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  assert command_module(
      path: "src/genesis_prime/game_master/teleport.gleam",
      rule: [
        "pub fn rule(",
        "  permissions permissions: List(String),",
        ") -> Result(List(Int), Refusal) {",
        "  Ok([])",
        "}",
      ],
    )
    == [6]
    as "the permissions are the account's set of permissions, not another type"
}

pub fn a_rule_whose_parameter_is_not_labelled_permissions_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  assert command_module(
      path: "src/genesis_prime/game_master/teleport.gleam",
      rule: [
        "pub fn rule(held: Set(Permission)) -> Result(List(Int), Refusal) {",
        "  Ok([])",
        "}",
      ],
    )
    == [6]
    as "the label names what the argument is at every call"
}

pub fn a_command_module_with_no_public_rule_is_a_breach_at_line_one_test() -> Nil {
  use <- owned_test.run(5000)
  assert command_module(
      path: "src/genesis_prime/game_master/teleport.gleam",
      rule: [
        "fn rule(permissions permissions: Set(Permission)) -> Int {",
        "  1",
        "}",
      ],
    )
    == [1]
    as "a private rule is no rule a process can call"
}

pub fn a_support_module_and_a_file_outside_game_master_are_never_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  let no_rule = ["pub fn other() -> Int {", "  1", "}"]
  assert command_module(
      path: "src/genesis_prime/game_master/store.gleam",
      rule: no_rule,
    )
    == []
    as "the store is a support module"
  assert command_module(
      path: "src/genesis_prime/game_master/permission.gleam",
      rule: no_rule,
    )
    == []
    as "the permission type is a support module"
  assert command_module(
      path: "src/genesis_prime/game_master/sql.gleam",
      rule: no_rule,
    )
    == []
    as "the generated queries are a support module"
  assert command_module(
      path: "src/genesis_prime/login/account_store.gleam",
      rule: no_rule,
    )
    == []
    as "a module outside game_master is no command"
}

pub fn every_command_module_in_the_tree_takes_the_account_permissions_test() -> Nil {
  // Deadline: the body took 85 to 97 ms in three runs alone, so 5 s is more
  // than 3 times that.
  use <- owned_test.run(5000)
  let files = repository.sources(["src"])
  assert list.any(files, fn(file) {
    file.path == "src/genesis_prime/game_master/grant.gleam"
  })
    as "the grant command module is in the tree, so the rule is not passing by finding nothing"
  assert list.flat_map(files, game_master_command.breaches) == []
}
