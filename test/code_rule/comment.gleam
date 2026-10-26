//// Comments describe the code as it stands: no history words, no links to
//// issues or pull requests, no dates, and no other codebase's name.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import gleam/list
import gleam/string
import glexer
import glexer/token

const history_words = [
  "now", "no longer", "used to", "not yet", "for now", "so far",
]

/// Names of other codebases a comment may not mention, written in lower case.
const other_codebases = [
  "nexusforever", "nexus forever", "eldan server", "eldan experiment",
  "eldan-experiment",
]

/// Each comment in the file that breaks the rule.
pub fn breaches(file: SourceFile) -> List(Breach) {
  glexer.new(file.text)
  |> glexer.discard_whitespace
  |> glexer.lex
  |> list.filter_map(fn(positioned) {
    let #(found, position) = positioned
    let text = token.to_source(found)
    case string.starts_with(text, "//") {
      True ->
        case reason(text) {
          Ok(reason) ->
            Ok(Breach(
              path: file.path,
              line: syntax.line_of(file.text, position.byte_offset),
              rule: "a comment that " <> reason,
            ))
          Error(Nil) -> Error(Nil)
        }
      False -> Error(Nil)
    }
  })
}

/// Why the comment breaks the rule, when it does.
fn reason(comment: String) -> Result(String, Nil) {
  let lowered = string.lowercase(comment)
  let checks = [
    #("uses a history word", fn() {
      list.any(history_words, contains_words(lowered, _))
    }),
    #("names an issue or pull request", fn() { names_an_issue(lowered) }),
    #("holds a date", fn() { has_date(<<lowered:utf8>>) }),
    #("names another codebase", fn() {
      list.any(other_codebases, string.contains(lowered, _))
    }),
  ]
  list.find_map(checks, fn(check) {
    case check.1() {
      True -> Ok(check.0)
      False -> Error(Nil)
    }
  })
}

/// Whether the phrase appears as whole words.
fn contains_words(text: String, phrase: String) -> Bool {
  let parts = string.split(text, phrase)
  list.zip(parts, list.drop(parts, 1))
  |> list.any(fn(neighbours) {
    !ends_with_word_character(neighbours.0)
    && !starts_with_word_character(neighbours.1)
  })
}

fn ends_with_word_character(text: String) -> Bool {
  case list.last(string.to_graphemes(text)) {
    Ok(grapheme) -> is_word_character(grapheme)
    Error(Nil) -> False
  }
}

fn starts_with_word_character(text: String) -> Bool {
  case string.first(text) {
    Ok(grapheme) -> is_word_character(grapheme)
    Error(Nil) -> False
  }
}

fn is_word_character(grapheme: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", grapheme)
}

/// A `#` followed by a digit, or a GitHub issue or pull request link.
fn names_an_issue(comment: String) -> Bool {
  hash_number(<<comment:utf8>>)
  || {
    string.contains(comment, "github.com/")
    && {
      string.contains(comment, "/issues/") || string.contains(comment, "/pull/")
    }
  }
}

fn hash_number(bytes: BitArray) -> Bool {
  case bytes {
    <<35, digit, _:bits>> if digit >= 48 && digit <= 57 -> True
    <<_, rest:bits>> -> hash_number(rest)
    _ -> False
  }
}

/// Four digits, a dash, two digits, a dash and two digits.
fn has_date(bytes: BitArray) -> Bool {
  case bytes {
    <<
      year:bytes-size(4),
      45,
      month:bytes-size(2),
      45,
      day:bytes-size(2),
      _:bits,
    >> ->
      case all_digits(year) && all_digits(month) && all_digits(day) {
        True -> True
        False -> has_date_after_first(bytes)
      }
    <<_, _:bits>> -> has_date_after_first(bytes)
    _ -> False
  }
}

fn has_date_after_first(bytes: BitArray) -> Bool {
  case bytes {
    <<_, rest:bits>> -> has_date(rest)
    _ -> False
  }
}

fn all_digits(bytes: BitArray) -> Bool {
  case bytes {
    <<digit, rest:bits>> if digit >= 48 && digit <= 57 -> all_digits(rest)
    <<>> -> True
    _ -> False
  }
}
