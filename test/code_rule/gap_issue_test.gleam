//// The gap-owner rule's tests. The expected values are CLAUDE.md's rule (a gap
//// names the open issue that will close it) and the shape of `gh issue list
//// --json number`; the planted files and open lists are made up here.

import code_rule/gap_issue.{Checked, NotChecked, NotRead}
import code_rule/planted
import code_rule/raw_type.{Gap}
import code_rule/repository
import gleam/io
import gleam/list
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

pub fn github_not_reached_is_reported_on_a_development_machine_and_fails_in_ci_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file = planted.file(path, ["/// Waits for issue 333."])
  let not_reached = Error(NotRead("no network"))
  assert gap_issue.verdict(
      files: [file],
      gaps: [],
      open_issues: not_reached,
      in_ci: False,
    )
    == NotChecked("no network")
  let assert Checked([breach]) =
    gap_issue.verdict(
      files: [file],
      gaps: [],
      open_issues: not_reached,
      in_ci: True,
    )
  assert breach.rule == "the open issues were not read in CI: no network"
  let assert Checked([closed]) =
    gap_issue.verdict(
      files: [file],
      gaps: [],
      open_issues: Ok([334]),
      in_ci: True,
    )
  assert closed.line == 1
  assert gap_issue.verdict(
      files: [file],
      gaps: [],
      open_issues: Ok([333]),
      in_ci: True,
    )
    == Checked([])
}

pub fn each_issue_a_comment_in_src_names_is_open_test() -> Nil {
  // Deadline: gh answers in about a second and the source is read once per
  // run; the 60 s `gh` limit sits inside this 90 s.
  use <- owned_test.run(90_000)
  use <- unitest.tag("code_rule")
  let verdict =
    gap_issue.verdict(
      files: repository.sources(["src"]),
      gaps: raw_type.known_gaps,
      open_issues: gap_issue.open_issues(),
      in_ci: gap_issue.in_ci(),
    )
  case verdict {
    Checked(breaches) -> {
      assert breaches == []
    }
    NotChecked(reason) ->
      io.println("gap owners not checked, open issues not read: " <> reason)
  }
}
