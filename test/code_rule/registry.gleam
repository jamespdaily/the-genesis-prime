//// The registry tests stay in the quick check. A test module that compares a
//// hand-kept list with a registry of the whole server holds a test tagged
//// `registry` (`use <- unitest.tag("registry")`), because `./check fast` runs the
//// tests of that tag and no others of the same files; an untagged module fails
//// in CI, in a branch that never touched it.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list
import gleam/string

const rule_name = "a registry test module with no public test tagged `registry`"

const registry_tag = "registry"

/// A breach, at line 1 of its file, for each of the named test modules (paths from
/// the repository root) that is among the files and holds no public test whose body
/// starts a `use <- unitest.tag("registry")`, and one for each named module that is
/// not among the files.
pub fn breaches(
  files files: List(SourceFile),
  modules modules: List(String),
) -> List(Breach) {
  list.filter_map(modules, fn(path) {
    case list.find(files, fn(file) { file.path == path }) {
      Error(Nil) ->
        Ok(Breach(path:, line: 1, rule: "the registry test module is missing"))
      Ok(file) ->
        case has_a_tagged_test(file) {
          True -> Error(Nil)
          False -> Ok(Breach(path:, line: 1, rule: rule_name))
        }
    }
  })
}

fn has_a_tagged_test(file: SourceFile) -> Bool {
  list.any(syntax.parse(file).functions, fn(definition) {
    let function = definition.definition
    function.publicity == glance.Public
    && string.ends_with(function.name, "_test")
    && list.any(function.body, is_the_tag)
  })
}

fn is_the_tag(statement: glance.Statement) -> Bool {
  case statement {
    glance.Use(
      patterns: [],
      function: glance.Call(
        function: glance.FieldAccess(
          container: glance.Variable(name: "unitest", ..),
          label: "tag",
          ..,
        ),
        arguments: [glance.UnlabelledField(glance.String(value:, ..))],
        ..,
      ),
      ..,
    ) -> value == registry_tag
    glance.Use(..)
    | glance.Assignment(..)
    | glance.Assert(..)
    | glance.Expression(_) -> False
  }
}
