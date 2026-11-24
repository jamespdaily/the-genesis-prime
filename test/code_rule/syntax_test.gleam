//// The names the syntax helpers give: the name an import goes by, and the
//// names a function binds. Expected values are the Gleam language's rules for
//// qualified names and for the names a pattern, a parameter or a closure
//// introduces.

import code_rule/planted
import code_rule/syntax
import glance
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

pub fn lines_of_offsets_in_any_order_and_at_the_end_of_the_text_are_each_given_their_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert syntax.lines_of(text: "ab\ncd\n\nf", byte_offsets: [7, 0, 3, 8, 5, 2])
    == [4, 1, 2, 4, 2, 1]
    as "offsets out of order, and the end of the text, each have their own line"
}

pub fn the_line_of_one_offset_is_the_line_of_that_byte_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert syntax.line_of(text: "ab\ncd", byte_offset: 3) == 2
    as "the byte after a newline starts the next line"
  assert syntax.line_of(text: "ab\ncd", byte_offset: 2) == 1
    as "a newline byte belongs to the line it ends"
  assert syntax.line_of(text: "ab", byte_offset: 2) == 1
    as "the end of the text is on the last line"
}

/// What the call at the top of a function body gives for a value: the integer
/// literal as written, `"other"` for any other expression, none for no
/// expression.
fn given(
  call call: String,
  label label: String,
  position position: syntax.Position,
) -> option.Option(String) {
  let module =
    syntax.parse(
      planted.file("src/planted.gleam", ["pub fn f() { " <> call <> " }"]),
    )
  let assert [first, ..] = syntax.calls(module) as "the body holds a call"
  case syntax.argument(arguments: first.arguments, label:, position:) {
    Some(glance.Int(value:, ..)) -> Some(value)
    Some(_) -> Some("other")
    None -> None
  }
}

pub fn a_value_a_call_gives_by_label_is_found_by_label_or_else_by_position_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #("g(1, 2)", syntax.LastArgument, Some("2"), "the last unlabelled one"),
      #("g(1, 2)", syntax.FirstArgument, Some("1"), "the first unlabelled one"),
      #(
        "g(1, within: 5)",
        syntax.LastArgument,
        Some("5"),
        "the label wins over the position",
      ),
      #(
        "g(1, 2, within: 3)",
        syntax.FirstArgument,
        Some("3"),
        "the label wins over the first",
      ),
      #(
        "g(x: 1)",
        syntax.FirstArgument,
        None,
        "a first argument with another label is not the value",
      ),
      #(
        "g(1, x: 2)",
        syntax.LastArgument,
        None,
        "a last argument with another label is not the value",
      ),
      #(
        "g(within:)",
        syntax.LastArgument,
        None,
        "a punned label has no expression",
      ),
      #("g()", syntax.FirstArgument, None, "no arguments, no value"),
      #(
        "g(within: foo(1))",
        syntax.FirstArgument,
        Some("other"),
        "any expression",
      ),
    ],
    fn(row) {
      let #(call, position, expected, reason) = row
      assert given(call:, label: "within", position:) == expected as reason
    },
  )
}

pub fn a_capture_is_a_call_with_the_arguments_around_its_hole_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert given(
      call: "g(1, _, 3)",
      label: "within",
      position: syntax.FirstArgument,
    )
    == Some("1")
    as "the arguments before the hole come first"
  assert given(call: "g(_, 2)", label: "within", position: syntax.LastArgument)
    == Some("2")
    as "the arguments after the hole follow"
  let module =
    syntax.parse(planted.file("src/planted.gleam", ["pub fn f() { g(1, _) }"]))
  assert list.length(syntax.calls(module)) == 1
    as "a capture is one call, not a call and a capture"
}

pub fn a_call_names_a_variable_or_a_function_of_a_variable_or_another_expression_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #("f(1)", syntax.CalledByName("f"), "a plain call names its variable"),
      #(
        "m.f(1)",
        syntax.CalledThroughVariable(variable: "m", label: "f"),
        "a call through a module names the module's variable and the label",
      ),
      #(
        "f(_)",
        syntax.CalledByName("f"),
        "a capture names its function as a call does",
      ),
      #(
        "m.f(_)",
        syntax.CalledThroughVariable(variable: "m", label: "f"),
        "a capture through a module names it as a call does",
      ),
      #(
        "m.n.f(1)",
        syntax.CalledOtherwise,
        "a field of a field is no variable's function",
      ),
      #("f(1)(2)", syntax.CalledOtherwise, "a call's result called again"),
      #(
        "fn(x) { x }(1)",
        syntax.CalledOtherwise,
        "an anonymous function called in place",
      ),
    ],
    fn(row) {
      let #(call, expected, reason) = row
      let module =
        syntax.parse(
          planted.file("src/planted.gleam", ["pub fn f() { " <> call <> " }"]),
        )
      let assert [first, ..] = syntax.calls(module) as "the body holds a call"
      assert first.called == expected as reason
    },
  )
}
