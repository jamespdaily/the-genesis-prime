//// The shape the code rules' checked-in lists share: one row per line, blank
//// lines ignored, and the rows sorted with none repeated.

import code_rule/source.{type Breach, Breach}
import gleam/int
import gleam/list
import gleam/order
import gleam/string

/// The non-blank rows of a list file, each trimmed and with its line of the
/// file (from 1).
pub fn rows(text text: String) -> List(#(String, Int)) {
  text
  |> string.split("\n")
  |> list.index_map(fn(row, index) { #(string.trim(row), index + 1) })
  |> list.filter(fn(entry) { entry.0 != "" })
}

/// The message of a row that does not have the words its list gives.
pub fn bad_row(line line: Int, what what: String) -> String {
  "line " <> int.to_string(line) <> " of the list " <> what
}

/// The rows of a list of two words each, with their line of the file. A row
/// that is not two words split by one space panics with `bad_row` and `what`.
pub fn pairs(
  text text: String,
  what what: String,
) -> List(#(String, String, Int)) {
  rows(text:)
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let assert [first, second] = string.split(row, " ") as bad_row(line:, what:)
    #(first, second, line)
  })
}

/// A breach at a row's line of its list file: the row's `name`, then `what`.
pub fn breach(
  path path: String,
  line line: Int,
  name name: String,
  what what: String,
) -> Breach {
  Breach(path:, line:, rule: name <> " " <> what)
}

/// A breach, at the row's line of the list file, for each row that is not
/// after the row before it by `compare`: out of order or repeated. `name`
/// writes the row for the breach's text, and `what` ends it.
pub fn disordered(
  rows rows: List(row),
  compare compare: fn(row, row) -> order.Order,
  path path: String,
  line line: fn(row) -> Int,
  name name: fn(row) -> String,
  what what: String,
) -> List(Breach) {
  list.zip(rows, list.drop(rows, 1))
  |> list.filter_map(fn(pair) {
    let #(before, row) = pair
    case compare(before, row) {
      order.Lt -> Error(Nil)
      order.Eq | order.Gt ->
        Ok(breach(path:, line: line(row), name: name(row), what:))
    }
  })
}
