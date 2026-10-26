//// Erlang source as the code rules read it: a line with its comment, its
//// strings and its quoted atoms taken out, and the names that line calls.

import gleam/list
import gleam/string

/// The line without its comment, its strings and its quoted atoms.
pub fn code_of(line: String) -> String {
  skip_text(graphemes: string.to_graphemes(line), reading: Code, kept: "")
}

type Reading {
  Code
  Quoted(closing: String)
  Escaped(closing: String)
  CharacterLiteral
}

/// The code in the graphemes, read in the state `reading` after `kept`.
fn skip_text(
  graphemes graphemes: List(String),
  reading reading: Reading,
  kept kept: String,
) -> String {
  case graphemes, reading {
    [], _ -> kept
    ["%", ..], Code -> kept
    ["$", ..rest], Code ->
      skip_text(graphemes: rest, reading: CharacterLiteral, kept: kept)
    ["\"", ..rest], Code ->
      skip_text(graphemes: rest, reading: Quoted("\""), kept: kept <> " ")
    ["'", ..rest], Code ->
      skip_text(graphemes: rest, reading: Quoted("'"), kept: kept <> " ")
    [grapheme, ..rest], Code ->
      skip_text(graphemes: rest, reading: Code, kept: kept <> grapheme)
    [_, ..rest], CharacterLiteral ->
      skip_text(graphemes: rest, reading: Code, kept: kept <> " ")
    ["\\", ..rest], Quoted(closing:) ->
      skip_text(graphemes: rest, reading: Escaped(closing:), kept: kept)
    [grapheme, ..rest], Quoted(closing:) if grapheme == closing ->
      skip_text(graphemes: rest, reading: Code, kept: kept)
    [_, ..rest], Quoted(closing:) ->
      skip_text(graphemes: rest, reading: Quoted(closing:), kept: kept)
    [_, ..rest], Escaped(closing:) ->
      skip_text(graphemes: rest, reading: Quoted(closing:), kept: kept)
  }
}

/// Whether the code holds the name as a whole name, not inside a longer one.
pub fn names(code: String, name: String) -> Bool {
  case string.split(code, name) {
    [] | [_] -> False
    [first, ..rest] -> whole_name_follows(name:, before: first, after: rest)
  }
}

/// `before` is the code up to a match of `name`, and `after` the pieces of
/// code that follow each match.
fn whole_name_follows(
  name name: String,
  before before: String,
  after after: List(String),
) -> Bool {
  case after {
    [] -> False
    [next, ..others] ->
      { !ends_in_name(before) && !starts_with_name(next) }
      || whole_name_follows(
        name:,
        before: before <> name <> next,
        after: others,
      )
  }
}

fn ends_in_name(text: String) -> Bool {
  case list.last(string.to_graphemes(text)) {
    Ok(grapheme) -> is_name_character(grapheme) || grapheme == ":"
    Error(Nil) -> False
  }
}

fn starts_with_name(text: String) -> Bool {
  case string.first(text) {
    Ok(grapheme) -> is_name_character(grapheme)
    Error(Nil) -> False
  }
}

fn is_name_character(grapheme: String) -> Bool {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@",
    grapheme,
  )
}

/// Whether the code holds the prefix, such as `logger:`, anywhere a name
/// could start: not after a character of a longer name or a colon, so
/// `my_logger:info` and `a:logger:info` do not hold `logger:`.
pub fn starts_name(code: String, prefix: String) -> Bool {
  case string.split(code, prefix) {
    [] | [_] -> False
    [first, ..rest] -> name_starts_after(prefix:, before: first, after: rest)
  }
}

fn name_starts_after(
  prefix prefix: String,
  before before: String,
  after after: List(String),
) -> Bool {
  case after {
    [] -> False
    [next, ..others] ->
      !ends_in_name(before)
      || name_starts_after(
        prefix:,
        before: before <> prefix <> next,
        after: others,
      )
  }
}
