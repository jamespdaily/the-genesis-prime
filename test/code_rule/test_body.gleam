//// Every test body runs inside `owned_test.run`.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/string

/// Each public test function in the file whose body does not start inside the helper.
pub fn breaches(file: SourceFile) -> List(Breach) {
  syntax.parse(file).functions
  |> list.sort(fn(first, second) {
    int.compare(
      first.definition.location.start,
      second.definition.location.start,
    )
  })
  |> list.filter(fn(definition) {
    let function = definition.definition
    function.publicity == glance.Public
    && string.ends_with(function.name, "_test")
    && !starts_inside_the_helper(function.body)
  })
  |> list.map(fn(definition) {
    Breach(
      path: file.path,
      line: syntax.line_of(file.text, definition.definition.location.start),
      rule: "a test body that does not start with `use <- owned_test.run(`",
    )
  })
}

fn starts_inside_the_helper(body: List(glance.Statement)) -> Bool {
  case body {
    [
      glance.Use(
        patterns: [],
        function: glance.Call(
          function: glance.FieldAccess(
            container: glance.Variable(name: "owned_test", ..),
            label: "run",
            ..,
          ),
          ..,
        ),
        ..,
      ),
      ..
    ] -> True
    [glance.Use(..), ..]
    | [glance.Assignment(..), ..]
    | [glance.Assert(..), ..]
    | [glance.Expression(_), ..]
    | [] -> False
  }
}
