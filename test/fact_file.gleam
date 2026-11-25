//// The client's fact file read by the tests, so a test that states a client
//// value takes it from the record that holds it and cannot differ from it.

import genesis_prime/coverage/fact_record
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

/// Why a fact could not be read.
pub type FactError {
  /// The fact file has no record of this name.
  NoRecord(name: String)
  /// The record's statement does not give these bytes.
  BytesNotGiven(name: String, bytes: BitArray)
}

/// Runs `create` once per key in this VM (the cache of `database_support.once`, which
/// this module cannot import: it sits below it).
@external(erlang, "database_support_ffi", "once")
fn once(key: String, create: fn() -> a) -> a

/// The records of the fact file, read once for the run
/// (genesis_prime/coverage/fact_record).
pub fn records() -> fact_record.Facts {
  once("fact_records", fn() {
    let assert Ok(facts) = fact_record.read()
      as "the fact file is readable TOML"
    facts
  })
}

/// The statement of the record `name`.
pub fn statement(record name: String) -> Result(String, FactError) {
  dict.get(records(), name)
  |> result.map(fn(record) { record.statement })
  |> result.replace_error(NoRecord(name:))
}

/// How sure the record `name` is, or the error when the file has no record of that
/// name. `None` when the record states no grade.
pub fn grade_of(
  record name: String,
) -> Result(Option(fact_record.Grade), FactError) {
  use <- bool.guard(
    when: !fact_record.has_record(facts: records(), key: name),
    return: Error(NoRecord(name:)),
  )
  Ok(fact_record.grade_of(facts: records(), key: name))
}

/// The question the record `name` leaves open (its gap), or the error when the file
/// has no record of that name. `None` when the record states no gap.
pub fn gap_of(record name: String) -> Result(Option(String), FactError) {
  use <- bool.guard(
    when: !fact_record.has_record(facts: records(), key: name),
    return: Error(NoRecord(name:)),
  )
  Ok(fact_record.gap_of(facts: records(), key: name))
}

/// Whether the record `name` gives `bytes` in its statement (`gives_bytes`).
pub fn gives(
  record name: String,
  bytes bytes: BitArray,
) -> Result(Nil, FactError) {
  use statement <- result.try(statement(record: name))
  case gives_bytes(statement:, bytes:) {
    True -> Ok(Nil)
    False -> Error(BytesNotGiven(name:, bytes:))
  }
}

/// Whether a statement gives `bytes`: they are written as lowercase hexadecimal
/// in whole bytes, in groups split by spaces, as the vector records write them
/// ("0c 00 00 00 44 02", or "aa3e0000 44332211"), the groups being a run of
/// the statement's words. A word is read after the punctuation that ends a
/// phrase is taken off, and a run stops at a word that ended a phrase, so the
/// bytes of two phrases ("00, 13") are never one run. An empty body is given by the words "its body is
/// empty" or "no bytes".
fn gives_bytes(statement statement: String, bytes bytes: BitArray) -> Bool {
  case bit_array.byte_size(bytes) {
    0 ->
      string.contains(statement, "body is empty")
      || string.contains(statement, "no bytes")
    _ -> {
      let target = string.lowercase(bit_array.base16_encode(bytes))
      let words =
        string.split(statement, on: " ")
        |> list.flat_map(string.split(_, on: "\n"))
        |> list.map(word_of)
      starts_a_run(words:, target:)
    }
  }
}

/// A word of the statement: its text in lowercase, without the opening bracket
/// or the punctuation after it, and whether punctuation ended a phrase after
/// it.
type Word {
  Word(text: String, ends_phrase: Bool)
}

fn word_of(word: String) -> Word {
  let text =
    string.lowercase(word)
    |> string.remove_prefix("(")
  let stripped = drop_end_punctuation(text)
  Word(text: stripped, ends_phrase: stripped != text)
}

fn drop_end_punctuation(word: String) -> String {
  let ends_a_phrase =
    string.ends_with(word, ",")
    || string.ends_with(word, ".")
    || string.ends_with(word, ";")
    || string.ends_with(word, ":")
    || string.ends_with(word, ")")
  use <- bool.guard(when: !ends_a_phrase, return: word)
  drop_end_punctuation(string.drop_end(word, 1))
}

/// Whether some run of the words, each a whole number of hexadecimal bytes,
/// is `target` when joined.
fn starts_a_run(words words: List(Word), target target: String) -> Bool {
  case words {
    [] -> False
    [_, ..later] ->
      run_from(words:, joined: "", target:)
      || starts_a_run(words: later, target:)
  }
}

fn run_from(
  words words: List(Word),
  joined joined: String,
  target target: String,
) -> Bool {
  case joined == target, words {
    True, _ -> True
    False, [] -> False
    False, [Word(text:, ends_phrase:), ..later] ->
      case is_whole_hexadecimal_bytes(text) {
        False -> False
        True -> {
          let longer = joined <> text
          case ends_phrase {
            True -> longer == target
            False ->
              string.starts_with(target, longer)
              && run_from(words: later, joined: longer, target:)
          }
        }
      }
  }
}

fn is_whole_hexadecimal_bytes(word: String) -> Bool {
  word != ""
  && string.length(word) % 2 == 0
  && list.all(string.to_graphemes(word), fn(digit) {
    string.contains("0123456789abcdef", digit)
  })
}
