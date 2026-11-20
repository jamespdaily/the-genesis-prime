//// The registry tests stay in the quick check. A test that compares a hand-kept
//// list with a registry of the whole server carries the tag `registry`, as
//// `use <- unitest.tag("registry")` or in `use <- unitest.tags([...])`, because
//// `./check fast` runs the tests of that tag and no others of the same files; an
//// untagged one fails in CI, in a branch that never touched it.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list
import gleam/string

const registry_tag = "registry"

/// A registry test the quick check must run: the test module (a path from the
/// repository root) and the start of the test's name, which is the whole name for a
/// test whose name does not change.
pub type RegistryTest {
  RegistryTest(path: String, name_start: String)
}

/// A breach for each named test that is missing from its module or whose body does
/// not start a `use <- unitest.tag("registry")` or `use <- unitest.tags([...])`
/// naming it, at the line of its function; and one, at line 1, for each named module
/// that is not among the files. A tag on another test of the module does not count.
pub fn breaches(
  files files: List(SourceFile),
  tests tests: List(RegistryTest),
) -> List(Breach) {
  list.filter_map(tests, fn(named) {
    case list.find(files, fn(file) { file.path == named.path }) {
      Error(Nil) ->
        Ok(Breach(
          path: named.path,
          line: 1,
          rule: "the registry test module is missing",
        ))
      Ok(file) -> breach_of_named_test(file, named)
    }
  })
}

fn breach_of_named_test(
  file: SourceFile,
  named: RegistryTest,
) -> Result(Breach, Nil) {
  let rule =
    "the registry test `"
    <> named.name_start
    <> "` is missing or has no `registry` tag"
  let candidates =
    list.filter(syntax.parse(file).functions, fn(definition) {
      let function = definition.definition
      function.publicity == glance.Public
      && string.ends_with(function.name, "_test")
      && string.starts_with(function.name, named.name_start)
    })
  case candidates {
    [] -> Ok(Breach(path: file.path, line: 1, rule:))
    [first, ..] ->
      case
        list.any(candidates, fn(definition) {
          list.any(definition.definition.body, is_the_tag)
        })
      {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: file.path,
            line: syntax.line_of(
              text: file.text,
              byte_offset: first.definition.location.start,
            ),
            rule:,
          ))
      }
  }
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
    glance.Use(
      patterns: [],
      function: glance.Call(
        function: glance.FieldAccess(
          container: glance.Variable(name: "unitest", ..),
          label: "tags",
          ..,
        ),
        arguments: [glance.UnlabelledField(glance.List(elements:, ..))],
        ..,
      ),
      ..,
    ) -> list.any(elements, is_the_tag_name)
    glance.Use(..)
    | glance.Assignment(..)
    | glance.Assert(..)
    | glance.Expression(_) -> False
  }
}

fn is_the_tag_name(expression: glance.Expression) -> Bool {
  case expression {
    glance.String(value:, ..) -> value == registry_tag
    glance.Variable(..)
    | glance.FieldAccess(..)
    | glance.Int(..)
    | glance.Float(..)
    | glance.NegateInt(..)
    | glance.NegateBool(..)
    | glance.Block(..)
    | glance.Panic(..)
    | glance.Todo(..)
    | glance.Tuple(..)
    | glance.List(..)
    | glance.Fn(..)
    | glance.RecordUpdate(..)
    | glance.Call(..)
    | glance.TupleIndex(..)
    | glance.FnCapture(..)
    | glance.BitString(..)
    | glance.Case(..)
    | glance.BinaryOperator(..)
    | glance.Echo(..) -> False
  }
}
