//// The gap-owner rule: every issue a comment in the server's source names, and
//// every issue a known raw-type gap names, is open. CLAUDE.md says a gap names
//// the open issue that will close it, and the writing-code skill allows an
//// issue in a comment only for that (and a patch marker's upstream bug), so a
//// closed issue in a comment is a gap whose owner is gone.
////
//// ```text
//// src files -> issues named in comments -> minus the open issues -> breaches
//// gh issue list --state open ------------^   (not read: skipped with a warning)
//// ```
////
//// - A citation is `#` and digits, or `issue` or `issues` and digits, in a
////   line that starts with `//` (a line, doc or module comment). A comment
////   after code on the same line is not read, and neither is a citation inside
////   double quotes that open before it and close after it on the line (a client
////   text such as "Auto-Attack #1").
//// - The open issues come from `gh`, in CI with the workflow's token. When
////   they cannot be read (gh missing, unreachable, rate-limited or answering
////   something else), the rule is skipped with a warning that names the reason, on
////   a development machine and in CI alike: a GitHub failure is no fault of the
////   code. Only an issue confirmed closed fails.

import code_rule/raw_type.{type Gap}
import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// Why the open issues could not be read.
pub type NotRead {
  NotRead(reason: String)
}

/// What the rule found: the breaches, or that the open issues were not read,
/// with the reason.
pub type Verdict {
  Checked(breaches: List(Breach))
  NotChecked(reason: String)
}

/// One issue named in a comment: the file, the line and the issue number.
pub type Citation {
  Citation(path: String, line: Int, issue: Int)
}

@external(erlang, "open_issue_ffi", "list_open")
fn list_open(deadline_milliseconds: Int) -> Result(String, NotRead)

/// The open issues of this repository from `gh`, within a minute.
pub fn open_issues() -> Result(List(Int), NotRead) {
  use output <- result.try(list_open(60_000))
  parse_open_issues(output)
}

/// The issue numbers in `gh issue list --json number`'s answer.
pub fn parse_open_issues(output: String) -> Result(List(Int), NotRead) {
  json.parse(
    output,
    decode.list({
      use number <- decode.field("number", decode.int)
      decode.success(number)
    }),
  )
  |> result.replace_error(NotRead("gh's answer is not a list of issue numbers"))
}

/// Each issue a comment line names, with the file and line, in order.
pub fn citations(files: List(SourceFile)) -> List(Citation) {
  list.flat_map(files, fn(file) {
    file.text
    |> string.split("\n")
    |> list.index_map(fn(text, index) { #(index + 1, text) })
    |> list.filter(fn(line) {
      string.starts_with(string.trim_start(line.1), "//")
    })
    |> list.flat_map(fn(line) {
      list.map(issue_numbers(line.1), fn(issue) {
        Citation(path: file.path, line: line.0, issue:)
      })
    })
  })
}

fn issue_numbers(text: String) -> List(Int) {
  let lowered = string.lowercase(text)
  let after_hash = after_each(lowered, "#")
  let after_word =
    after_each(lowered, "issue")
    |> list.map(fn(rest) {
      string.trim_start(case string.starts_with(rest, "s") {
        True -> string.drop_start(rest, 1)
        False -> rest
      })
    })
  list.filter_map(list.append(after_hash, after_word), leading_number)
}

/// The text after each occurrence of `marker` that is not inside double quotes
/// (a client text such as "Auto-Attack #1" is no issue). It is inside when an
/// odd number of quotes comes before it on the line and another follows; the end
/// of a title quoted over two lines does not count.
fn after_each(text: String, marker: String) -> List(String) {
  case string.split(text, marker) {
    [] -> []
    [first, ..rest] ->
      after_unquoted(parts: rest, before: first, marker:, found: [])
  }
}

fn after_unquoted(
  parts parts: List(String),
  before before: String,
  marker marker: String,
  found found: List(String),
) -> List(String) {
  case parts {
    [] -> list.reverse(found)
    [part, ..rest] -> {
      let quote_marks = list.length(string.split(before, "\"")) - 1
      let inside_quotes = quote_marks % 2 == 1 && string.contains(part, "\"")
      let found = case inside_quotes {
        False -> [part, ..found]
        True -> found
      }
      after_unquoted(
        parts: rest,
        before: before <> marker <> part,
        marker:,
        found:,
      )
    }
  }
}

fn leading_number(text: String) -> Result(Int, Nil) {
  text
  |> string.to_graphemes
  |> list.take_while(fn(grapheme) { result.is_ok(int.parse(grapheme)) })
  |> string.concat
  |> int.parse
}

/// A breach for each citation, and each raw-type gap, naming an issue that is
/// not open, at the citation's file and line (a gap's at line 1 of its file).
pub fn breaches(
  files files: List(SourceFile),
  gaps gaps: List(Gap),
  open_issues open_issues: List(Int),
) -> List(Breach) {
  let cited =
    citations(files)
    |> list.filter(fn(citation) { !list.contains(open_issues, citation.issue) })
    |> list.map(fn(citation) {
      Breach(
        path: citation.path,
        line: citation.line,
        rule: "the comment names issue "
          <> int.to_string(citation.issue)
          <> ", which is not open (it closed after this comment was written, or"
          <> " this was no gap): name the open issue that now holds the gap, or"
          <> " drop the citation",
      )
    })
  let listed =
    gaps
    |> list.filter(fn(gap) { !list.contains(open_issues, gap.issue) })
    |> list.map(fn(gap) {
      Breach(
        path: gap.path,
        line: 1,
        rule: "the known gap for `"
          <> gap.function
          <> "` names issue "
          <> int.to_string(gap.issue)
          <> ", which is not open: name the open issue that now holds the gap in"
          <> " `raw_type.known_gaps`",
      )
    })
  list.append(cited, listed)
}

/// The rule's verdict from what `gh` answered. When the open issues could not be
/// read, the rule is skipped with the reason, in CI as on a development machine;
/// only an issue confirmed closed is a breach.
pub fn verdict(
  files files: List(SourceFile),
  gaps gaps: List(Gap),
  open_issues open_issues: Result(List(Int), NotRead),
) -> Verdict {
  case open_issues {
    Ok(open) -> Checked(breaches(files:, gaps:, open_issues: open))
    Error(NotRead(reason)) -> NotChecked(reason)
  }
}
