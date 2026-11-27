//// The let-assert rule. A `let assert` with no `as` message, or with an empty
//// one, is a breach at its line. A module with more of them than its row of the
//// ceiling list is a breach at the first one past the row; a module with none
//// listed has a ceiling of 0. A row above its module's count (or for a module
//// that holds none or is gone) is a breach at the row's list line, so a stale
//// row is never slack for a new assert. The list must be in order, one row per
//// module, and hold at most `most_rows` rows. Every case is planted; the last
//// test runs the rule over the real `src/` and `dev/` and the real list.
//// A list row that is not two words or has no integer ceiling stops the test
//// through an `as` message, so it is not a planted case.

import code_rule/let_assert.{Listed}
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import unitest

/// A planted file at `path` with one function whose body is the lines (the
/// first of them at line 2).
fn function_file(path: String, body: List(String)) -> SourceFile {
  planted.file(path, list.flatten([["pub fn f() {"], body, ["}"]]))
}

/// A planted module `src/planted.gleam` whose body is the lines.
fn planted_file(body: List(String)) -> SourceFile {
  function_file("src/planted.gleam", body)
}

/// A module at `path` with `count` asserts that each have a message, one per
/// line from line 2.
fn messaged(path: String, count: Int) -> SourceFile {
  function_file(
    path,
    list.repeat("  let assert Ok(_) = g() as \"holds\"", count),
  )
}

/// The breach lines of the planted module `planted` whose body is the lines,
/// listed at exactly the number of asserts it holds, so only the messages count.
fn message_breaches(body: List(String)) -> List(Int) {
  let file = planted_file(body)
  let held = list.length(syntax.let_asserts(syntax.parse(file)))
  planted.lines(let_assert.breaches(
    files: [file],
    listed: [Listed("planted", held, 1)],
    most_rows: 1,
  ))
}

pub fn let_asserts_are_found_in_every_statement_list_with_their_line_and_message_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(
        ["  let assert Ok(a) = g() as \"x\"", "  a"],
        [#(2, True)],
        "a function body",
      ),
      #(["  let assert Ok(a) = g()", "  a"], [#(2, False)], "no message"),
      #(
        ["  {", "    let assert Ok(a) = g() as \"x\"", "    a", "  }"],
        [#(3, True)],
        "a block",
      ),
      #(
        ["  fn() {", "    let assert Ok(a) = g()", "    a", "  }"],
        [#(3, False)],
        "a fn body",
      ),
      #(
        [
          "  case g() {",
          "    Ok(a) -> {",
          "      let assert Ok(b) = h(a) as \"x\"",
          "      b",
          "    }",
          "    Error(_) -> 1",
          "  }",
        ],
        [#(4, True)],
        "a multi-statement case arm",
      ),
      #(
        [
          "  let assert Ok(a) = g() as \"x\"",
          "  fn() {",
          "    {",
          "      let assert Ok(b) = h(a)",
          "      b",
          "    }",
          "  }",
        ],
        [#(2, True), #(5, False)],
        "a nested one is found with the one around it",
      ),
      #(
        [
          "  let a = g()",
          "  assert a == 1",
          "  // let assert Ok(b) = h()",
          "  let c = \"let assert Ok(b) = h()\"",
          "  a",
        ],
        [],
        "a let, an assert, a comment and a string hold none",
      ),
    ],
    fn(row) {
      let #(body, expected, reason) = row
      let file = planted_file(body)
      let found = syntax.let_asserts(syntax.parse(file))
      let lines =
        syntax.lines_of(
          text: file.text,
          byte_offsets: list.map(found, fn(found) { found.start }),
        )
      assert list.zip(
          lines,
          list.map(found, fn(found) { found.message != None }),
        )
        == expected
        as reason
    },
  )
}

pub fn a_let_assert_with_no_message_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(["  let assert Ok(a) = g()", "  a"], [2], "bare"),
      #(["  let assert Ok(a) =", "    g()", "  a"], [2], "over two lines"),
      #(
        ["  fn() {", "    let assert Ok(a) = g()", "    a", "  }"],
        [3],
        "nested in a fn",
      ),
      #(
        [
          "  let assert Ok(a) = g() as \"x\"",
          "  let assert Ok(b) = h(a)",
          "  b",
        ],
        [3],
        "the one without a message among ones with",
      ),
    ],
    fn(row) {
      let #(body, lines, reason) = row
      assert message_breaches(body) == lines as reason
    },
  )
}

pub fn a_let_assert_with_an_empty_message_is_a_breach_and_a_stated_one_passes_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #("\"\"", [2], "an empty string"),
      #("\"x\"", [], "a string"),
      #("{ \"x\" <> int.to_string(n) }", [], "a built message"),
    ],
    fn(row) {
      let #(message, lines, reason) = row
      assert message_breaches(["  let assert Ok(a) = g() as " <> message, "  a"])
        == lines
        as reason
    },
  )
}

pub fn a_module_over_its_ceiling_is_one_breach_at_the_assert_that_crossed_it_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let stated = "let assert Ok(_) = g() as \"x\""
  list.each(
    [
      #(
        messaged("src/planted.gleam", 3),
        2,
        [4],
        "the third assert is the one past a ceiling of 2",
      ),
      #(
        planted.file("src/planted.gleam", [
          "pub fn old() {",
          "  " <> stated,
          "  1",
          "}",
          "pub fn new() {",
          "  " <> stated,
          "  1",
          "}",
        ]),
        1,
        [6],
        "an assert in a function below the one that holds the ceiling is the one that crossed it",
      ),
      #(
        planted_file([
          "  {",
          "    " <> stated,
          "    1",
          "  }",
          "  " <> stated,
          "  1",
        ]),
        1,
        [6],
        "an assert in the body below a block that holds one is the one that crossed it",
      ),
    ],
    fn(row) {
      let #(file, ceiling, lines, reason) = row
      assert planted.lines(let_assert.breaches(
          files: [file],
          listed: [Listed("planted", ceiling, 1)],
          most_rows: 1,
        ))
        == lines
        as reason
    },
  )
}

pub fn a_module_at_its_ceiling_or_with_no_assert_and_no_row_passes_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #([messaged("src/planted.gleam", 2)], [Listed("planted", 2, 1)], "at it"),
      #([messaged("src/planted.gleam", 0)], [], "no assert and no row"),
    ],
    fn(row) {
      let #(files, listed, reason) = row
      assert let_assert.breaches(
          files:,
          listed:,
          most_rows: list.length(listed),
        )
        == []
        as reason
    },
  )
}

pub fn a_module_with_asserts_and_no_row_is_a_breach_at_its_first_assert_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert planted.lines(let_assert.breaches(
      files: [messaged("src/planted.gleam", 2)],
      listed: [],
      most_rows: 0,
    ))
    == [2]
    as "a module with no row has a ceiling of 0"
}

pub fn a_row_above_its_modules_count_is_a_breach_at_its_list_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(2, 3, "write 2", "a count of 2 under a row of 3"),
      #(0, 1, "delete the row", "a count of 0 under a row of 1"),
    ],
    fn(row_case) {
      let #(count, ceiling, said, reason) = row_case
      let breaches =
        let_assert.breaches(
          files: [messaged("src/planted.gleam", count)],
          listed: [Listed("planted", ceiling, 7)],
          most_rows: 1,
        )
      assert planted.lines(breaches) == [7] as reason
      assert list.all(breaches, fn(breach) {
        breach.path == let_assert.list_path
        && string.contains(breach.rule, said)
      })
        as { reason <> ": the breach is in the list and says " <> said }
    },
  )
}

pub fn a_row_for_a_module_that_is_gone_is_a_breach_at_its_list_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #([], Listed("gone", 2, 3), "a row of 2 for a module that is gone"),
      #([], Listed("gone", 0, 3), "a row of 0 for a module that is gone"),
      #([], Listed("gone", -2, 3), "a row below 0 for a module that is gone"),
      #(
        [messaged("src/planted.gleam", 0)],
        Listed("planted", 0, 3),
        "a row of 0 for a module that holds none",
      ),
    ],
    fn(row) {
      let #(files, entry, reason) = row
      assert planted.lines(let_assert.breaches(
          files:,
          listed: [entry],
          most_rows: 1,
        ))
        == [3]
        as reason
    },
  )
}

pub fn a_row_out_of_order_or_repeated_or_past_the_most_rows_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let first = messaged("src/a.gleam", 1)
  let second = messaged("src/b.gleam", 1)
  list.each(
    [
      #(
        [first],
        [Listed("a", 1, 1), Listed("a", 1, 2)],
        2,
        [2],
        "a repeated row",
      ),
      #(
        [first, second],
        [Listed("b", 1, 1), Listed("a", 1, 2)],
        2,
        [2],
        "out of order",
      ),
      #(
        [first, second],
        [Listed("a", 1, 1), Listed("b", 1, 2)],
        2,
        [],
        "in order",
      ),
      #(
        [first, second],
        [Listed("a", 1, 1), Listed("b", 1, 2)],
        1,
        [2],
        "past the most rows",
      ),
      #(
        [first, second],
        [Listed("a", 1, 1), Listed("b", 1, 2)],
        2,
        [],
        "at the most rows",
      ),
      #(
        [first, second],
        [Listed("a", 1, 1), Listed("b", 1, 2)],
        3,
        [2],
        "fewer rows than the most rows",
      ),
    ],
    fn(row_case) {
      let #(files, listed, most, lines, reason) = row_case
      assert planted.lines(let_assert.breaches(files:, listed:, most_rows: most))
        == lines
        as reason
    },
  )
}

pub fn the_list_is_read_as_module_and_ceiling_per_line_from_line_1_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #("a 1\nb/c 22\n", [Listed("a", 1, 1), Listed("b/c", 22, 2)], "two rows"),
      #(
        "\na 1\n\n  b 2  \n",
        [Listed("a", 1, 2), Listed("b", 2, 4)],
        "blank lines are skipped and counted",
      ),
      #("", [], "an empty list"),
    ],
    fn(row_case) {
      let #(text, expected, reason) = row_case
      assert let_assert.parse_list(text) == expected as reason
    },
  )
}

pub fn every_let_assert_of_src_and_dev_has_a_message_and_stays_within_its_ceiling_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(["src", "dev"])
  assert list.all(files, fn(file) { file.text != "" })
    as "every file read holds text"
  let breaches =
    let_assert.breaches(
      files:,
      listed: let_assert.parse_list(source.read(let_assert.list_path)),
      most_rows: let_assert.most_rows,
    )
  assert breaches == []
    as {
      int.to_string(list.length(breaches))
      <> " breaches, the first: "
      <> string.inspect(list.first(breaches))
    }
}
