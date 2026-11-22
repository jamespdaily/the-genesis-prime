//// The skipped-tag rule. Expected values are the rule of the check: a tag the
//// test run skips (`skipped_when_set` in `test/genesis_prime_test.gleam`) has
//// its tests run by a part of `./check` that runs the tag by itself. The
//// breaches are planted in made-up files; the last test runs the rule over the
//// real files.

import code_rule/planted
import code_rule/repository
import code_rule/skipped_tag
import code_rule/source.{type SourceFile, SourceFile}
import gleam/list
import gleam/string
import owned_test
import unitest

/// The planted test run: `ignored_tags` holds the entries, the first of them on
/// line 9.
fn test_run(entries: List(String)) -> SourceFile {
  planted.file(
    "test/genesis_prime_test.gleam",
    list.flatten([
      [
        "import gleam/list",
        "import unitest",
        "",
        "pub fn main() {",
        "  unitest.run(",
        "    unitest.Options(",
        "      ..unitest.default_options(),",
        "      ignored_tags: list.flatten([",
      ],
      entries,
      ["      ]),", "    ),", "  )", "}"],
    ]),
  )
}

fn skip(tag: String) -> String {
  "        skipped_when_set(\"GENESIS_TEST_SKIP_"
  <> string.uppercase(tag)
  <> "\", tag: \""
  <> tag
  <> "\"),"
}

fn part(tag: String) -> String {
  "  GENESIS_TEST_PROGRESS_FILE=\"$work/"
  <> tag
  <> ".running\" run_built genesis_prime_test --tag "
  <> tag
}

fn check(lines: List(String)) -> SourceFile {
  planted.file("check", lines)
}

fn breach_lines(
  entries entries: List(String),
  check_lines check_lines: List(String),
) -> List(Int) {
  skipped_tag.breaches(test_run: test_run(entries), check: check(check_lines))
  |> planted.lines
}

pub fn a_skipped_tag_no_check_part_runs_is_a_breach_naming_the_tag_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let breaches =
    skipped_tag.breaches(
      test_run: test_run([skip("serial"), skip("slow")]),
      check: check(["# the parts", part("serial")]),
    )
  let assert [breach] = breaches as "expected one breach, for `slow`"
  assert breach.path == "test/genesis_prime_test.gleam"
  assert breach.line == 10 as "the line of the skipped_when_set call of slow"
  assert string.contains(breach.rule, "`slow`")
}

pub fn a_skipped_tag_a_part_runs_is_no_breach_and_a_tag_named_in_a_comment_or_an_echo_is_not_a_part_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the planted entries, the planted check's lines, the breach lines,
  // and why.
  let cases = [
    #([skip("x")], [part("x")], [], "a skipped tag with its part"),
    #(
      [skip("x"), skip("y")],
      [part("x"), part("y")],
      [],
      "two skipped tags with a part each",
    ),
    #([], [], [], "no skipped tag"),
    #(
      [skip("x")],
      [
        "    ( GENESIS_TEST_PROGRESS_FILE=\"$work/x.running\" step x-part run_built genesis_prime_test --tag x ) &",
      ],
      [],
      "the part inside a subshell started by a step",
    ),
    #(
      [skip("x")],
      ["# run_built genesis_prime_test --tag x"],
      [9],
      "the tag named only in a comment line",
    ),
    #([skip("x")], ["  # " <> part("x")], [9], "the part itself commented out"),
    #(
      [skip("x")],
      ["  echo \"run_built genesis_prime_test --tag x\""],
      [9],
      "the tag named only in an echo",
    ),
    #(
      [skip("x")],
      ["  printf 'run_built genesis_prime_test --tag x\\n'"],
      [9],
      "the tag named only in a printf",
    ),
    #(
      [skip("x")],
      ["  skip x-part \"run_built genesis_prime_test --tag x\""],
      [9],
      "the tag named only in a message string",
    ),
    #(
      [skip("x")],
      [
        "  skip x-part \"by hand: run_built genesis_prime_test --tag x later\"",
      ],
      [9],
      "the tag named in a message string with words after it",
    ),
    #(
      [skip("x")],
      ["  skip x-part 'by hand: run_built genesis_prime_test --tag x later'"],
      [9],
      "the tag named in a single-quoted message with words after it",
    ),
    #(
      [skip("x")],
      ["  true # run_built genesis_prime_test --tag x"],
      [9],
      "the tag named in a trailing comment",
    ),
    #(
      [skip("x")],
      [
        "cat <<EOF",
        "run_built genesis_prime_test --tag x",
        "EOF",
      ],
      [9],
      "the tag named only in the text of a heredoc",
    ),
    #(
      [skip("x")],
      [
        "cat <<'EOF'",
        "run_built genesis_prime_test --tag x",
        "EOF",
      ],
      [9],
      "the tag named only in the text of a quoted-word heredoc",
    ),
    #(
      [skip("x")],
      ["cat <<EOF", "text", "EOF", part("x")],
      [],
      "a part after a heredoc is a part",
    ),
    #(
      [skip("x")],
      [part("x") <> " # the part of x"],
      [],
      "a part with a trailing comment is a part",
    ),
    #(
      [skip("x")],
      ["  step \"x part\" run_built genesis_prime_test --tag x &"],
      [],
      "a part started by a step with a quoted name is a part",
    ),
    #([skip("x")], [part("y")], [9], "a part for another tag"),
    #(
      [skip("x")],
      ["  run_built other_test --tag x"],
      [9],
      "the tag of a run of another program",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(entries, check_lines, lines, reason) = case_
    assert breach_lines(entries:, check_lines:) == lines as reason
  })
}

pub fn an_ignored_tag_that_is_not_a_skipped_when_set_with_a_literal_tag_is_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the planted entries (the first on line 9), the breach lines, and
  // why. Every tag is run by a part, so a breach is the unreadable entry.
  let cases = [
    #([skip("a")], [], "a readable entry"),
    #(["        \"serial\","], [9], "a bare string"),
    #(
      ["        other_helper(\"A\", tag: \"y\"),"],
      [9],
      "another helper's call",
    ),
    #(
      ["        skipped_when_set(\"A\", tag: some_constant),"],
      [9],
      "a constant for the tag",
    ),
    #(
      ["        skipped_when_set(\"A\", \"a\"),"],
      [],
      "the tag given by position is read",
    ),
    #(
      [
        skip("a"),
        "        some_constant,",
        skip("a"),
        "        skipped_when_set(\"A\", tag: tag_of(1)),",
      ],
      [10, 12],
      "each unreadable entry among readable ones, at its own line",
    ),
    #(
      [
        "        list.append(skipped_when_set(\"A\", tag: \"a\"), [skipped_when_set(\"A\", tag: \"a\")]),",
      ],
      [],
      "entries joined by list.append are read",
    ),
    #(
      ["        list.append(skipped_when_set(\"A\", tag: \"a\"), [\"b\"]),"],
      [9],
      "a bare string inside list.append",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(entries, lines, reason) = case_
    assert breach_lines(entries:, check_lines: [part("a"), part("b")]) == lines
      as reason
  })
  let without_ignored_tags =
    planted.file("test/genesis_prime_test.gleam", [
      "pub fn main() {",
      "  unitest.run(unitest.default_options())",
      "}",
    ])
  assert skipped_tag.breaches(
      test_run: without_ignored_tags,
      check: check([part("a")]),
    )
    |> planted.lines
    == [1]
    as "a test run with no ignored_tags is a breach, so the rule cannot pass by finding nothing"
}

/// The tags the check sets to skip in the test run, read from the variables
/// `GENESIS_TEST_SKIP_X=1` of its gleam-test part: a second source for the
/// tags the test run skips.
fn skip_variables_of(check: SourceFile) -> List(String) {
  check.text
  |> string.split("\n")
  |> list.flat_map(string.split(_, " "))
  |> list.filter_map(fn(word) {
    let prefix = "GENESIS_TEST_SKIP_"
    case string.starts_with(word, prefix) && string.ends_with(word, "=1") {
      True ->
        Ok(
          word
          |> string.drop_start(string.length(prefix))
          |> string.drop_end(2)
          |> string.lowercase,
        )
      False -> Error(Nil)
    }
  })
  |> list.unique
  |> list.sort(string.compare)
}

pub fn every_tag_the_test_run_skips_is_run_by_a_part_of_the_check_test() -> Nil {
  // Deadline: the body took under 300 ms alone, so 5 s is more than 10 times that.
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(["test"])
  let assert Ok(test_run) =
    list.find(files, fn(file) { file.path == "test/genesis_prime_test.gleam" })
  let check = SourceFile(path: "check", text: source.read("check"))
  assert skipped_tag.breaches(test_run:, check:) == []
  let skipped = skipped_tag.skipped_tags(test_run)
  assert skipped != [] as "the rule finds the tags the run skips"
  assert list.sort(skipped, string.compare) == skip_variables_of(check)
    as "the tags the rule reads are the ones the check sets variables for"
}
