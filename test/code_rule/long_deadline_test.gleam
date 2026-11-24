//// The long-deadline rule. Expected values are the rule: a test's deadline
//// (`owned_test.run(N)` and its variants) above 10 000 ms is a breach unless the
//// comment block directly above the call holds a `// deadline:` line that
//// names a measured number, or the test is on the list of the long deadlines
//// that exist today, keyed by module and test, with the deadline it has as its
//// ceiling. A listed test that no longer has a deadline above 10 000 ms, one that
//// names its cause too, and one that is above its ceiling are breaches, so the
//// list holds exactly the tests that have no cause. A deadline the rule cannot
//// read (not an integer literal) is a breach. Every case is planted in a
//// made-up file; the last test runs the rule over the real test tree and its list.

import code_rule/long_deadline.{type Listed, Listed}
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import gleam/int
import gleam/list
import owned_test
import unitest

/// A planted test file whose test `long_test` is at line 3; `above` is the
/// lines between the opening of the function and the call (line 4 on), and
/// `call` is the call's line.
fn planted_test(above: List(String), call: String) -> SourceFile {
  planted.file(
    "test/planted_test.gleam",
    list.flatten([
      ["import owned_test", "", "pub fn long_test() {"],
      above,
      [call, "  assert 1 == 1", "}"],
    ]),
  )
}

fn listed_at(ceiling_ms: Int, line: Int) -> List(Listed) {
  [Listed(module: "planted_test", test_name: "long_test", ceiling_ms:, line:)]
}

/// Each row: the lines above the call, the call, the list, the lines of the
/// breaches, and why.
fn check_rows(
  rows: List(#(List(String), String, List(Listed), List(Int), String)),
) -> Nil {
  list.each(rows, fn(row) {
    let #(above, call, listed, lines, reason) = row
    assert planted.lines(long_deadline.breaches(
        files: [planted_test(above, call)],
        listed:,
      ))
      == lines
      as reason
  })
}

const call_60 = "  use <- owned_test.run(60_000)"

pub fn a_deadline_above_10_000_with_its_measured_cause_passes_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      [
        "  // deadline: the file ran in 31 s alone, 2 s a test, so 60 s is twice",
      ],
      call_60,
      [],
      [],
      "a cause on the line above passes",
    ),
    #(
      [
        "  // deadline: the whole table is read, 38 s alone on the",
        "  // slowest machine, so 60 s",
      ],
      call_60,
      [],
      [],
      "a cause that goes on over several comment lines passes",
    ),
    #(
      ["  // a note", "  // deadline: 12 s alone"],
      call_60,
      [],
      [],
      "the deadline line may follow another comment line",
    ),
    #([], "  use <- owned_test.run(10_000)", [], [], "10 000 is not above"),
    #(
      [],
      "  use <- owned_test.run(5000)",
      [],
      [],
      "a short deadline needs none",
    ),
  ])
}

pub fn a_deadline_above_10_000_with_no_measured_cause_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #([], call_60, [], [4], "no comment"),
    #(["  // slow"], call_60, [], [5], "a comment that is no deadline line"),
    #(
      ["  // deadline: it is slow"],
      call_60,
      [],
      [5],
      "a deadline line with no measured number",
    ),
    #(["  // deadline:"], call_60, [], [5], "a deadline line with no words"),
    #(
      ["  // deadline: 12 s alone", ""],
      call_60,
      [],
      [6],
      "a blank line between the comment and the call",
    ),
    #(
      ["  // deadline: 12 s alone", "  use <- unitest.tag(\"code_rule\")"],
      call_60,
      [],
      [6],
      "the comment must be directly above the call",
    ),
    #(
      [],
      "  use <- owned_test.run(120_000)",
      listed_at(60_000, 1),
      [4],
      "a listed test over its ceiling with no cause",
    ),
  ])
}

pub fn a_listed_test_with_a_deadline_at_or_below_its_ceiling_passes_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #([], call_60, listed_at(60_000, 1), [], "a listed test at its ceiling"),
    #([], call_60, listed_at(90_000, 1), [], "a listed test under its ceiling"),
    #(
      [],
      "  use <- owned_test.run(10_001)",
      listed_at(10_001, 1),
      [],
      "a listed test just above 10 000",
    ),
  ])
}

pub fn a_listed_test_with_no_deadline_above_10_000_is_a_breach_at_its_list_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      [],
      "  use <- owned_test.run(10_000)",
      listed_at(60_000, 7),
      [7],
      "a listed test at 10 000 is stale",
    ),
    #(
      [],
      "  use <- owned_test.run(5000)",
      listed_at(60_000, 7),
      [7],
      "a listed test under 10 000 is stale",
    ),
    #(
      [],
      call_60,
      [
        Listed(
          module: "planted_test",
          test_name: "long_test",
          ceiling_ms: 60_000,
          line: 6,
        ),
        Listed(
          module: "planted_test",
          test_name: "gone_test",
          ceiling_ms: 60_000,
          line: 7,
        ),
        Listed(
          module: "gone_test",
          test_name: "long_test",
          ceiling_ms: 60_000,
          line: 8,
        ),
      ],
      [7, 8],
      "a listed test or module that is no longer there is stale",
    ),
  ])
  let assert [breach] =
    long_deadline.breaches(
      files: [planted_test([], "  use <- owned_test.run(10_000)")],
      listed: listed_at(60_000, 7),
    )
    as "one breach"
  assert breach.path == long_deadline.list_path
    as "the breach is in the list file"
}

pub fn a_listed_test_that_names_its_cause_is_a_breach_at_its_list_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      ["  // deadline: 12 s alone, so 60 s"],
      call_60,
      listed_at(60_000, 9),
      [9],
      "a listed test with a cause is off the list",
    ),
  ])
}

pub fn the_other_calls_of_the_runner_are_read_too_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      [],
      "  use <- owned_test.run_under_salt(salt: \"s\", timeout_ms: 60_000)",
      [],
      [4],
      "run_under_salt's timeout_ms",
    ),
    #(
      [],
      "  use <- owned_test.run_warning_to(warn: fn(_) { Nil }, progress_file: None, timeout_ms: 30_000)",
      [],
      [4],
      "run_warning_to's timeout_ms",
    ),
    #(
      [],
      "  use <- owned_test.run_listed_in(progress_file: None, timeout_ms: 30_000)",
      [],
      [4],
      "run_listed_in's timeout_ms",
    ),
    #(
      ["  // deadline: 3 s alone"],
      "  use <- owned_test.run_under_salt(salt: \"s\", timeout_ms: 60_000)",
      [],
      [],
      "a cause above a variant passes",
    ),
    #(
      [],
      "  use <- owned_test.run(timeout_ms: 60_000)",
      [],
      [4],
      "a labelled deadline of run",
    ),
  ])
}

pub fn a_deadline_that_is_not_an_integer_literal_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      ["  let limit = 60_000"],
      "  use <- owned_test.run(limit)",
      [],
      [5],
      "a variable",
    ),
    #(
      ["  // deadline: 12 s alone"],
      "  use <- owned_test.run(limit_ms)",
      [],
      [5],
      "a variable is a breach whatever the comment says",
    ),
    #(
      [],
      "  use <- owned_test.run_under_salt(salt: \"s\", timeout_ms:)",
      [],
      [4],
      "a punned label",
    ),
    #(
      ["  let run = owned_test.run"],
      "  use <- run(5000)",
      [],
      [4],
      "the function taken as a value",
    ),
  ])
}

pub fn a_module_imported_under_an_alias_is_read_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "import owned_test as owned",
      "",
      "pub fn long_test() {",
      "  use <- owned.run(60_000)",
      "  assert 1 == 1",
      "}",
    ])
  assert planted.lines(long_deadline.breaches(files: [file], listed: [])) == [4]
}

pub fn the_list_is_read_as_module_test_and_ceiling_per_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  assert long_deadline.parse_list(
      "a_test first_test 60000\nb/c_test second_test 120000\n",
    )
    == [
      Listed(
        module: "a_test",
        test_name: "first_test",
        ceiling_ms: 60_000,
        line: 1,
      ),
      Listed(
        module: "b/c_test",
        test_name: "second_test",
        ceiling_ms: 120_000,
        line: 2,
      ),
    ]
}

pub fn every_deadline_in_the_test_directory_is_short_or_names_its_cause_or_is_listed_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let listed = long_deadline.parse_list(source.read(long_deadline.list_path))
  assert listed != [] as "the list holds the long deadlines that stand"
  let breaches =
    long_deadline.breaches(files: repository.sources(["test"]), listed:)
  assert breaches == []
    as { int.to_string(list.length(breaches)) <> " breaches" }
}
