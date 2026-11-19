//// The gap-owner rule's tests. The expected values are CLAUDE.md's rule (a gap
//// names the open issue that will close it) and the shape of `gh issue list
//// --json number`; the planted files and open lists are made up here.

import code_rule/gap_issue.{Checked, NotChecked, NotRead}
import code_rule/planted
import code_rule/raw_type.{Gap}
import code_rule/repository
import gleam/io
import gleam/list
import gleam/string
import owned_test
import unitest

const path = "src/genesis_prime/game/planted.gleam"

pub fn a_comment_naming_a_closed_issue_fails_naming_the_file_and_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path, [
      "//// A planted module.",
      "",
      "/// The strike is not read (gap, #333).",
      "pub fn one() { 1 }",
      "/// The aim waits for issue 334.",
      "pub fn two() { 2 }",
    ])
  let breaches = gap_issue.breaches(files: [file], gaps: [], open_issues: [334])
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) })
    == [#(path, 3)]
  let assert [breach] = breaches
  assert string.contains(breach.rule, "issue 333")
}

pub fn a_comment_naming_an_open_issue_passes_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path, [
      "/// The strike is not read (gap, #333).",
      "pub fn one() { 1 }",
      "/// The aim waits for issue 334 and for issues 336.",
      "pub fn two() { 2 }",
    ])
  assert gap_issue.breaches(
      files: [file],
      gaps: [Gap(path:, function: "one", sites: 1, issue: 333)],
      open_issues: [333, 334, 336],
    )
    == []
}

pub fn a_raw_type_gap_naming_a_closed_issue_fails_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let gaps = [
    Gap(path:, function: "open", sites: 1, issue: 333),
    Gap(path:, function: "closed", sites: 1, issue: 888),
  ]
  let breaches = gap_issue.breaches(files: [], gaps:, open_issues: [333])
  assert list.map(breaches, fn(breach) { #(breach.path, breach.line) })
    == [#(path, 1)]
}

pub fn a_citation_is_read_from_comments_only_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(path, [
      "//// Module comment, issue 11.",
      "/// Doc comment, #22, and Issues 33.",
      "    // An indented line comment (#44).",
      "pub fn code() { \"#55 and issue 66\" }",
      "pub fn hex() { 0x1403 } // after code, #77",
      "/// A hash with no number (#), a hex 0x140550c50, an issue with no number: issue.",
      "/// Two in a line, #88 and issue 99.",
      "/// the end of a title quoted over two lines\" (#13).",
      "/// A client text, \"Auto-Attack #1\", then #12 outside it.",
    ])
  assert list.map(gap_issue.citations([file]), fn(citation) {
      #(citation.line, citation.issue)
    })
    == [
      #(1, 11),
      #(2, 22),
      #(2, 33),
      #(3, 44),
      #(7, 88),
      #(7, 99),
      #(8, 13),
      #(9, 12),
    ]
}

pub fn the_open_issue_list_is_read_from_gh_output_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let cases = [
    #("[{\"number\":5},{\"number\":9}]", Ok([5, 9])),
    #("[]", Ok([])),
    #("not json", Error(NotRead("gh's answer is not a list of issue numbers"))),
    #(
      "[{\"title\":\"no number\"}]",
      Error(NotRead("gh's answer is not a list of issue numbers")),
    ),
  ]
  list.each(cases, fn(row) {
    assert gap_issue.parse_open_issues(row.0) == row.1
  })
}

pub fn only_an_issue_confirmed_closed_fails_and_a_github_failure_skips_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file = planted.file(path, ["/// Waits for issue 333."])
  let skipped = fn(reason) { NotChecked(reason) }
  // Each row: what gh gave (answers as `open_issues` builds them from gh's exit
  // and output), the verdict, and why.
  let cases = [
    #(Error(NotRead("gh is not installed")), skipped("gh is not installed")),
    #(
      Error(NotRead("gh exited with status 1 (rate limited)")),
      skipped("gh exited with status 1 (rate limited)"),
    ),
    #(
      gap_issue.parse_open_issues("warning: not json"),
      skipped("gh's answer is not a list of issue numbers"),
    ),
    #(Ok([333]), Checked([])),
  ]
  list.each(cases, fn(row) {
    assert gap_issue.verdict(files: [file], gaps: [], open_issues: row.0)
      == row.1
  })
  let assert Checked([closed]) =
    gap_issue.verdict(files: [file], gaps: [], open_issues: Ok([334]))
  assert closed.line == 1
  assert string.contains(closed.rule, "issue 333")
}

pub fn each_issue_a_comment_in_src_names_is_open_test() -> Nil {
  // Deadline: gh answers in about a second and the source is read once per
  // run; the 60 s `gh` limit sits inside this 90 s. Tagged `github` so a
  // repeated run, which reads the network and not the code under repeat, skips it
  // (`GENESIS_TEST_SKIP_GITHUB`).
  use <- owned_test.run(90_000)
  use <- unitest.tags(["code_rule", "github"])
  let verdict =
    gap_issue.verdict(
      files: repository.sources(["src"]),
      gaps: raw_type.known_gaps,
      open_issues: gap_issue.open_issues(),
    )
  case verdict {
    Checked(breaches) -> {
      assert breaches == []
    }
    NotChecked(reason) ->
      io.println(
        "WARNING: gap owners not checked, the open issues were not read: "
        <> reason,
      )
  }
}
