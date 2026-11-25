//// The client's fact file as records: the one Gleam reader of it. A record holds
//// its statement, its grade and, where the record states one, its gap, which is
//// the question the record leaves open. The coverage measure and the tests ask it
//// whether a cited fact exists, how sure it is and what it leaves open.
////
//// ```
//// client-facts.toml ─▶ parse ─▶ Facts (record name ─▶ Record) ─▶ has_record, grade_of, gap_of
//// ```
////
//// - **A record's name is its whole table key**, dots included: the fact checker's
////   `check_facts.py` loads the same file and enforces each record's fields.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile
import tom

/// The fact file.
const path = ".claude/skills/decoding-the-client/references/client-facts.toml"

/// How sure a record is.
pub type Grade {
  Sure
  FairlySure
  Guess
}

/// One record of the fact file: what it states, how sure it is and the question it
/// leaves open, when it names one.
pub type Record {
  Record(statement: String, grade: Option(Grade), gap: Option(String))
}

/// Every record of the fact file by its name.
pub type Facts =
  Dict(String, Record)

/// Why the fact file could not be read.
pub type FactFileError {
  /// The file could not be read from disk.
  Unreadable
  /// The text is not TOML.
  NotToml
  /// A record is not a table of the text fields the checker allows.
  BadRecord(name: String)
}

/// The fact file of the repository, read from disk.
pub fn read() -> Result(Facts, FactFileError) {
  use text <- result.try(
    simplifile.read(path) |> result.replace_error(Unreadable),
  )
  parse(text:)
}

/// The records of a fact file's text.
pub fn parse(text text: String) -> Result(Facts, FactFileError) {
  use document <- result.try(tom.parse(text) |> result.replace_error(NotToml))
  dict.to_list(document)
  |> list.try_map(record_of)
  |> result.map(dict.from_list)
}

fn record_of(
  entry: #(String, tom.Toml),
) -> Result(#(String, Record), FactFileError) {
  let #(name, value) = entry
  let bad = BadRecord(name:)
  case value {
    tom.Table(fields) | tom.InlineTable(fields) -> {
      use statement <- result.try(
        tom.get_string(fields, ["statement"]) |> result.replace_error(bad),
      )
      use grade <- result.try(case tom.get_string(fields, ["grade"]) {
        Ok("sure") -> Ok(Some(Sure))
        Ok("fairly sure") -> Ok(Some(FairlySure))
        Ok("guess") -> Ok(Some(Guess))
        Ok(_) | Error(tom.WrongType(..)) -> Error(bad)
        Error(tom.NotFound(_)) -> Ok(None)
      })
      use gap <- result.map(case tom.get_string(fields, ["gap"]) {
        Ok(gap) -> Ok(Some(gap))
        Error(tom.WrongType(..)) -> Error(bad)
        Error(tom.NotFound(_)) -> Ok(None)
      })
      #(name, Record(statement:, grade:, gap:))
    }
    _ -> Error(bad)
  }
}

/// Whether the facts hold a record named `key`.
pub fn has_record(facts facts: Facts, key key: String) -> Bool {
  dict.has_key(facts, key)
}

/// The record `key`'s grade, or `None` when it has no record or no grade.
pub fn grade_of(facts facts: Facts, key key: String) -> Option(Grade) {
  dict.get(facts, key)
  |> result.map(fn(record) { record.grade })
  |> option.from_result
  |> option.flatten
}

/// The record `key`'s gap, or `None` when it has no record or states no gap.
pub fn gap_of(facts facts: Facts, key key: String) -> Option(String) {
  dict.get(facts, key)
  |> result.map(fn(record) { record.gap })
  |> option.from_result
  |> option.flatten
}
