//// The long-deadline rule. Expected values are the rule: a test's deadline
//// (`owned_test.run(N)` and its variants) above 10 000 ms is a breach unless the
//// comment block directly above the call holds a `// deadline:` line that
//// names a measured time with its unit, or the test is on the list of the long
//// deadlines that have no cause, keyed by module and test, with the deadline it
//// has as its ceiling. A listed test above its ceiling is a breach; a list row
//// for a test that is gone, renamed, named or short is none. The list cannot grow:
//// more rows than the most it may hold, a repeated row and a row out of order are
//// breaches. A deadline the rule cannot read (not an integer literal) is a
//// breach. Every case is planted in a made-up file; the last test runs the rule
//// over the real test tree and its list.

import code_rule/long_deadline.{type Listed, Listed}
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile, SourceFile}
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

/// The runners as the rule reads them from the real `owned_test`.
fn runners() -> List(String) {
  long_deadline.runners_of(owned_test_source())
}

fn owned_test_source() -> SourceFile {
  SourceFile(
    path: "test/owned_test.gleam",
    text: source.read("test/owned_test.gleam"),
  )
}

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

fn listed_row(
  module module: String,
  test_name test_name: String,
  line line: Int,
) -> Listed {
  Listed(module:, test_name:, ceiling_ms: 60_000, line:)
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
        runners: runners(),
        listed:,
        most_rows: 100,
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
    #(
      ["  // deadline: 300ms a row, 40 rows"],
      call_60,
      [],
      [],
      "a unit written against its number passes",
    ),
    #(["  // deadline: 2 minutes alone"], call_60, [], [], "minutes are a unit"),
    #(
      ["  // deadline: 1.5 s alone"],
      call_60,
      [],
      [],
      "a fractional time passes",
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
    #(["  // deadline: 1"], call_60, [], [5], "a number with no unit"),
    #(
      ["  // deadline: see #1336"],
      call_60,
      [],
      [5],
      "an issue number is no time",
    ),
    #(
      ["  // deadline: raised 2026-11-24"],
      call_60,
      [],
      [5],
      "a date is no time",
    ),
    #(
      ["  // deadline: 12 so"],
      call_60,
      [],
      [5],
      "a word that only starts with a unit",
    ),
    #(["  // deadline: s"], call_60, [], [5], "a unit with no number"),
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

pub fn a_list_row_for_a_test_that_is_gone_renamed_short_or_named_is_no_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  check_rows([
    #(
      [],
      "  use <- owned_test.run(10_000)",
      listed_at(60_000, 1),
      [],
      "a listed test cut to 10 000 is no breach",
    ),
    #(
      [],
      "  use <- owned_test.run(5000)",
      listed_at(60_000, 1),
      [],
      "a listed test under 10 000 is no breach",
    ),
    #(
      [],
      call_60,
      [
        listed_row(module: "gone_test", test_name: "long_test", line: 1),
        listed_row(module: "planted_test", test_name: "gone_test", line: 2),
        listed_row(module: "planted_test", test_name: "long_test", line: 3),
      ],
      [],
      "a listed test or module that is no longer there is no breach",
    ),
    #(
      ["  // deadline: 12 s alone, so 60 s"],
      call_60,
      listed_at(60_000, 1),
      [],
      "a listed test that names its cause too is no breach",
    ),
  ])
}

pub fn a_list_past_its_most_rows_is_a_breach_at_its_last_row_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file = planted_test([], "  use <- owned_test.run(600_000)")
  let listed = [
    listed_row(module: "other_test", test_name: "long_test", line: 1),
    Listed(
      module: "planted_test",
      test_name: "long_test",
      ceiling_ms: 600_000,
      line: 2,
    ),
  ]
  assert planted.lines(long_deadline.breaches(
      files: [file],
      runners: runners(),
      listed:,
      most_rows: 1,
    ))
    == [2]
    as "a new test at 600 000 gets a row only by growing the list, which is a breach"
  assert long_deadline.breaches(
      files: [file],
      runners: runners(),
      listed:,
      most_rows: 2,
    )
    == []
    as "a list at its most is no breach"
  let assert [breach] =
    long_deadline.breaches(
      files: [file],
      runners: runners(),
      listed:,
      most_rows: 1,
    )
    as "one breach"
  assert breach.path == long_deadline.list_path
    as "the breach is in the list file"
  assert string.contains(breach.rule, "// deadline:")
    as "the breach says to name the cause"
}

pub fn a_repeated_row_or_a_row_out_of_order_is_a_breach_at_its_list_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  list.each(
    [
      #(
        [
          listed_row(module: "planted_test", test_name: "long_test", line: 1),
          Listed(
            module: "planted_test",
            test_name: "long_test",
            ceiling_ms: 600_000,
            line: 2,
          ),
        ],
        [2],
        "a test listed twice, the second with a higher ceiling",
      ),
      #(
        [
          listed_row(module: "b_test", test_name: "long_test", line: 1),
          listed_row(module: "a_test", test_name: "long_test", line: 2),
        ],
        [2],
        "a module before the one it follows",
      ),
      #(
        [
          listed_row(module: "a_test", test_name: "second_test", line: 1),
          listed_row(module: "a_test", test_name: "first_test", line: 2),
        ],
        [2],
        "a test before the one it follows",
      ),
      #(
        [
          listed_row(module: "a_test", test_name: "first_test", line: 1),
          listed_row(module: "a_test", test_name: "second_test", line: 2),
          listed_row(module: "b_test", test_name: "first_test", line: 3),
        ],
        [],
        "rows in order",
      ),
    ],
    fn(row) {
      let #(listed, lines, reason) = row
      assert planted.lines(long_deadline.breaches(
          files: [],
          runners: runners(),
          listed:,
          most_rows: 100,
        ))
        == lines
        as reason
    },
  )
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
    #(
      [],
      "  use <- owned_test.run(60_000, _)",
      [],
      [4],
      "a capture of the runner is read by its deadline",
    ),
    #(
      [],
      "  use <- owned_test.run(5000, _)",
      [],
      [],
      "a capture with a short deadline passes",
    ),
  ])
}

pub fn a_runner_is_each_public_function_of_owned_test_that_takes_a_timeout_ms_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let owned =
    planted.file("test/owned_test.gleam", [
      "pub fn run(timeout_ms: Int, body: fn() -> a) -> a { body() }",
      "pub fn run_listed_in(progress_file progress_file: Int, timeout_ms timeout_ms: Int, body body: fn() -> a) -> a { body() }",
      "pub fn deadline_warning(seconds: Int) -> Int { seconds }",
      "fn run_salted(timeout_ms: Int) -> Int { timeout_ms }",
      "pub fn tag(body: fn() -> a) -> a { body() }",
    ])
  assert long_deadline.runners_of(owned) == ["run", "run_listed_in"]
    as "a public function with a timeout_ms by name or by label, and no other"
  let file =
    planted.file("test/planted_test.gleam", [
      "import owned_test",
      "",
      "pub fn long_test() {",
      "  use <- owned_test.run_new(timeout_ms: 60_000)",
      "  assert 1 == 1",
      "}",
    ])
  let with_new_runner =
    long_deadline.runners_of(
      planted.file("test/owned_test.gleam", [
        "pub fn run_new(timeout_ms timeout_ms: Int) -> Int { timeout_ms }",
      ]),
    )
  assert planted.lines(long_deadline.breaches(
      files: [file],
      runners: with_new_runner,
      listed: [],
      most_rows: 100,
    ))
    == [4]
    as "a runner added to owned_test is read with no change to the rule"
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
      [],
      "  use <- owned_test.run_under_salt(\"s\", 60_000, fn() { Nil })",
      [],
      [4],
      "a deadline given by position after a salt",
    ),
    #(
      ["  let run = owned_test.run"],
      "  use <- run(5000)",
      [],
      [4],
      "the function taken as a value",
    ),
  ])
  let assert [breach] =
    long_deadline.breaches(
      files: [
        planted_test([], "  use <- owned_test.run_under_salt(\"s\", 60_000, b)"),
      ],
      runners: runners(),
      listed: [],
      most_rows: 100,
    )
    as "one breach"
  assert string.contains(breach.rule, "timeout_ms")
    as "the breach says to pass the deadline by its label"
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
  assert planted.lines(long_deadline.breaches(
      files: [file],
      runners: runners(),
      listed: [],
      most_rows: 100,
    ))
    == [4]
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
  let runners = runners()
  assert runners != [] as "the runners are found in test/owned_test.gleam"
  let listed = long_deadline.parse_list(source.read(long_deadline.list_path))
  let breaches =
    long_deadline.breaches(
      files: repository.sources(["test"]),
      runners:,
      listed:,
      most_rows: long_deadline.most_rows,
    )
  assert breaches == []
    as { int.to_string(list.length(breaches)) <> " breaches" }
}
