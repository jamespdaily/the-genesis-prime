//// The names the syntax helpers give: the name an import goes by, and the
//// names a function binds. Expected values are the Gleam language's rules for
//// qualified names and for the names a pattern, a parameter or a closure
//// introduces.

import code_rule/planted
import code_rule/syntax
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import unitest

/// Each import's module and the name it goes by, in module order.
fn imports_of(lines: List(String)) -> List(#(String, option.Option(String))) {
  let module = syntax.parse(planted.file("src/planted.gleam", lines))
  list.map(module.imports, fn(definition) {
    #(definition.definition.module, syntax.import_name(definition.definition))
  })
  |> list.sort(by: fn(first, second) { string.compare(first.0, second.0) })
}

pub fn an_import_goes_by_its_alias_or_its_last_segment_and_not_when_discarded_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert imports_of([
      "import gleam/list",
      "import genesis_prime/game/quest_log as log",
      "import gleam/io as _",
      "import gleam/option.{type Option}",
    ])
    == [
      #("genesis_prime/game/quest_log", Some("log")),
      #("gleam/io", None),
      #("gleam/list", Some("list")),
      #("gleam/option", Some("option")),
    ]
}

pub fn a_function_binds_its_parameters_lets_closures_and_patterns_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let module =
    syntax.parse(
      planted.file("src/planted.gleam", [
        "pub fn bound(parameter: Int, _ignored: Int) -> Int {",
        "  let assigned = 1",
        "  let #(first, _) = #(1, 2)",
        "  use used <- run()",
        "  let closure = fn(closed) {",
        "    let inside = closed",
        "    inside",
        "  }",
        "  case parameter {",
        "    Ok(found) | Error(found) as whole -> found",
        "    [head, ..tail] -> head",
        "    \"a\" <> rest -> rest",
        "    Row(label:, other: field) -> field",
        "  }",
        "}",
      ]),
    )
  let assert [definition] = module.functions
  let names =
    syntax.bound_names(definition.definition)
    |> list.unique
    |> list.sort(by: string.compare)
  assert names
    == [
      "assigned", "closed", "closure", "field", "first", "found", "head",
      "inside", "label", "parameter", "rest", "tail", "used", "whole",
    ]
}

pub fn many_byte_offsets_are_given_their_lines_in_one_read_of_the_text_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert syntax.lines_of(text: "ab\ncd\n\nf", byte_offsets: [0, 2, 3, 5, 6, 7])
    == [1, 1, 2, 2, 3, 4]
    as "a newline byte belongs to the line it ends; a blank line has its own number"
  assert syntax.lines_of(text: "é\nx", byte_offsets: [0, 3]) == [1, 2]
    as "offsets count bytes, not characters"
  assert syntax.lines_of(text: "ab", byte_offsets: [1, 0]) == [1, 1]
    as "the lines come in the order of the offsets"
}
