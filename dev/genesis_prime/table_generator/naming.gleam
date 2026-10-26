//// Gleam names for the client's table and column names. A table `Creature2`
//// is the module `creature2` and the type `Creature2`; a column
//// `donutDrawDistance` is the field `donut_draw_distance`. A name that is a
//// Gleam keyword gets a trailing underscore.

import gleam/list
import gleam/string

/// Why a client name has no Gleam name.
pub type NameError {
  /// The name is empty, or has a character other than letters, digits and
  /// underscores, or does not start with a letter.
  NotAName(client_name: String)
}

/// Words Gleam reserves, which a field name may not be.
const keywords = [
  "as", "assert", "auto", "case", "const", "delegate", "derive", "echo", "else",
  "fn", "if", "implement", "import", "let", "macro", "opaque", "panic", "pub",
  "test", "todo", "type", "use",
]

/// The snake-case form of a client name: a word starts at an upper-case letter
/// that follows a lower-case letter or digit, and at the last upper-case letter
/// of a run that a lower-case letter follows.
fn snake_case(client_name: String) -> Result(String, NameError) {
  let letters = string.to_graphemes(client_name)
  case valid(letters) {
    False -> Error(NotAName(client_name))
    True ->
      Ok(
        split_words(letters:, previous: "", words: [])
        |> list.reverse
        |> string.concat,
      )
  }
}

fn valid(letters: List(String)) -> Bool {
  case letters {
    [first, ..] ->
      is_letter(first)
      && list.all(letters, fn(letter) { is_name_character(letter) })
    [] -> False
  }
}

fn is_upper(letter: String) -> Bool {
  letter != string.lowercase(letter) && letter == string.uppercase(letter)
}

fn is_lower(letter: String) -> Bool {
  letter != string.uppercase(letter) && letter == string.lowercase(letter)
}

fn is_digit(letter: String) -> Bool {
  list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], letter)
}

fn is_letter(letter: String) -> Bool {
  letter_in_ascii(letter) && { is_upper(letter) || is_lower(letter) }
}

fn letter_in_ascii(letter: String) -> Bool {
  case string.to_utf_codepoints(letter) {
    [codepoint] -> string.utf_codepoint_to_int(codepoint) < 128
    _ -> False
  }
}

fn is_name_character(letter: String) -> Bool {
  is_letter(letter) || is_digit(letter) || letter == "_"
}

/// The letters in lower case, in reverse, each with an underscore before it
/// where a word starts.
fn split_words(
  letters letters: List(String),
  previous previous: String,
  words words: List(String),
) -> List(String) {
  case letters {
    [] -> words
    [letter, ..rest] -> {
      let starts_word = case is_upper(letter) {
        False -> False
        True ->
          is_lower(previous)
          || is_digit(previous)
          || { is_upper(previous) && next_is_lower(rest) }
      }
      let piece = case starts_word {
        True -> "_" <> string.lowercase(letter)
        False -> string.lowercase(letter)
      }
      split_words(letters: rest, previous: letter, words: [piece, ..words])
    }
  }
}

fn next_is_lower(letters: List(String)) -> Bool {
  case letters {
    [next, ..] -> is_lower(next)
    [] -> False
  }
}

/// The module name of a table: its snake-case name.
pub fn module_name(table: String) -> Result(String, NameError) {
  snake_case(table)
}

/// The type and constructor name of a table: the client's name, which is
/// already in upper camel case.
pub fn type_name(table: String) -> Result(String, NameError) {
  case string.to_graphemes(table), snake_case(table) {
    [first, ..], Ok(_) ->
      case is_upper(first) {
        True -> Ok(table)
        False -> Error(NotAName(table))
      }
    _, Error(error) -> Error(error)
    [], Ok(_) -> Error(NotAName(table))
  }
}

/// The field name of a column: its snake-case name, with a trailing
/// underscore when that is a Gleam keyword.
pub fn field_name(column: String) -> Result(String, NameError) {
  case snake_case(column) {
    Ok(name) ->
      case list.contains(keywords, name) {
        True -> Ok(name <> "_")
        False -> Ok(name)
      }
    Error(error) -> Error(error)
  }
}
