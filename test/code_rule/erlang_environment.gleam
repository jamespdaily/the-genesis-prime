//// The Erlang environment rule: no Erlang file reads an environment variable
//// or the command-line arguments itself. Gleam reads them through envoy and
//// argv, packages already in the tree, which come before an Erlang external
//// in the package order of the writing-gleam skill.

import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/list
import gleam/string

const forbidden = ["os:getenv", "init:get_plain_arguments"]

/// Each line of the Erlang file that calls or refers to `os:getenv` (of any
/// arity) or `init:get_plain_arguments`. Text in a comment (from `%` to the end
/// of the line), in a string or in a quoted atom is not read, and a longer name
/// that starts or ends with one of them is not a match.
pub fn breaches(file: SourceFile) -> List(Breach) {
  string.split(file.text, "\n")
  |> list.index_map(fn(line, index) { #(index + 1, code_of(line)) })
  |> list.filter(fn(numbered) { list.any(forbidden, names(numbered.1, _)) })
  |> list.map(fn(numbered) {
    Breach(
      path: file.path,
      line: numbered.0,
      rule: "an Erlang file that reads the environment or the arguments; use envoy or argv",
    )
  })
}

/// The line without its comment, its strings and its quoted atoms.
fn code_of(line: String) -> String {
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
fn names(code: String, name: String) -> Bool {
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
