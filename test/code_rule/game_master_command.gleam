//// The game master command rule: every command module under
//// `src/genesis_prime/game_master/` has a public `rule` function whose
//// parameter labelled `permissions` is the account's permissions, so no
//// command decides without checking them. The modules that are no command
//// are listed in `support_modules`.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list
import gleam/option.{Some}
import gleam/string

/// The modules of `game_master` that are no command: the permission type, what
/// every command shares, the store, and the generated queries.
pub const support_modules = [
  "genesis_prime/game_master/permission",
  "genesis_prime/game_master/command",
  "genesis_prime/game_master/store",
  "genesis_prime/game_master/sql",
]

/// The breach of a command module that has no public `rule` (at line 1), or
/// whose `rule` has no parameter labelled `permissions` of type
/// `Set(Permission)` (at the line of the `rule`). A file outside
/// `game_master`, and a support module, is never a breach.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  let module = syntax.module_name(file.path)
  case
    string.starts_with(module, "genesis_prime/game_master/"),
    list.contains(support_modules, module)
  {
    True, False -> command_breaches(file)
    _, _ -> []
  }
}

fn command_breaches(file: SourceFile) -> List(Breach) {
  let public_rules =
    syntax.parse(file).functions
    |> list.filter(fn(definition) {
      definition.definition.name == "rule"
      && definition.definition.publicity == glance.Public
    })
  case public_rules {
    [] -> [
      Breach(
        path: file.path,
        line: 1,
        rule: "a game master command module with no public rule",
      ),
    ]
    rules ->
      list.filter_map(rules, fn(definition) {
        case list.any(definition.definition.parameters, takes_permissions) {
          True -> Error(Nil)
          False ->
            Ok(Breach(
              path: file.path,
              line: syntax.line_of(
                file.text,
                definition.definition.location.start,
              ),
              rule: "a game master command rule that does not take the account's permissions as `permissions: Set(Permission)`",
            ))
        }
      })
  }
}

/// Whether a parameter is labelled `permissions` and typed `Set(Permission)`,
/// the type written bare or with its module's name.
fn takes_permissions(parameter: glance.FunctionParameter) -> Bool {
  case parameter.label, parameter.type_ {
    Some("permissions"),
      Some(glance.NamedType(
        name: "Set",
        parameters: [glance.NamedType(name: "Permission", ..)],
        ..,
      ))
    -> True
    _, _ -> False
  }
}
