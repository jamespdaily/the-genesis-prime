//// No line of `src` or `dev` names an issue, and no comment there says gap. A
//// gap is stated by an entry of its module's `gaps()`, which the coverage
//// measure prints; an issue is kept on GitHub, never in the code, so the
//// measure's text carries no issue number.
////
//// ```text
//// file lines -> issue rule (every line) + gap rule (comment lines) -> breaches
//// ```
////
//// - The issue rule: a line holds `#` and two digits or more, or the whole word
////   issue or issues in any case. The client's "Auto-Attack #1", hex and `#(`
////   tuples are not citations. Every line is read, comment, string and code.
//// - The gap rule: a comment line (leading `//`) holds the whole word gap or
////   gaps in any case. A name in backticks is an identifier and is not read.
//// - A word has no letter beside it; a digit, `_`, `-` or any other mark is a
////   separator, so `gap_issue` is a citation and `issued` is not.
//// - Only the line that holds the marker is tested.

import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/int
import gleam/list
import gleam/string

const issue_rule_name = "a line that names an issue"

const gap_rule_name = "a comment that states a gap in prose"

/// Each line of the file that names an issue, and each comment line that says
/// gap, at its line; a line breaking both is reported once for each rule.
pub fn breaches(file file: SourceFile) -> List(Breach) {
  file.text
  |> string.split("\n")
  |> list.index_map(fn(text, index) { #(index + 1, text) })
  |> list.flat_map(fn(numbered) {
    let #(line, text) = numbered
    let issue = case names_an_issue(text) {
      True -> [Breach(path: file.path, line:, rule: issue_rule_name)]
      False -> []
    }
    let gap = case is_comment(text) && says_gap(text) {
      True -> [Breach(path: file.path, line:, rule: gap_rule_name)]
      False -> []
    }
    list.append(issue, gap)
  })
}

/// Whether the line holds `#` and two digits, or the word issue or issues.
fn names_an_issue(text: String) -> Bool {
  has_hash_and_digits(text) || list.any(words(text), is_issue_word)
}

fn is_issue_word(word: String) -> Bool {
  word == "issue" || word == "issues"
}

/// Whether a `#` is followed by two digits: `#55`, not `#1` or `#(`.
fn has_hash_and_digits(text: String) -> Bool {
  text
  |> string.split("#")
  |> list.drop(1)
  |> list.any(fn(after) {
    case string.to_graphemes(after) {
      [first, second, ..] -> is_digit(first) && is_digit(second)
      _ -> False
    }
  })
}

fn is_digit(grapheme: String) -> Bool {
  string.contains("0123456789", grapheme)
}

fn is_comment(text: String) -> Bool {
  string.starts_with(string.trim_start(text), "//")
}

/// Whether the comment, less its backticked names, holds the word gap or gaps.
fn says_gap(text: String) -> Bool {
  text
  |> string.split("`")
  |> list.index_map(fn(part, index) { #(index, part) })
  |> list.filter(fn(numbered) { int.is_even(numbered.0) })
  |> list.any(fn(numbered) {
    list.any(words(numbered.1), fn(word) { word == "gap" || word == "gaps" })
  })
}

/// The lowercase runs of letters of a text.
fn words(text: String) -> List(String) {
  text
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(grapheme) {
    case string.contains("abcdefghijklmnopqrstuvwxyz", grapheme) {
      True -> grapheme
      False -> " "
    }
  })
  |> string.concat
  |> string.split(" ")
  |> list.filter(fn(word) { word != "" })
}
