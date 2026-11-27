//// The person-as-source rule: no tracked line under `src/`, `test/` or `dev/`
//// names Jim, except the lines of the keep list. A person is never the source
//// of a value or a decision in the code; the source is a client address, a
//// table row, a recording, a retail record, or "the server's choice".
////
//// ```
//// each file ──► its lines holding the word Jim
////                 │ no row of the list holds the line ─► breach at the line
//// the list ──► a row whose file holds no such line     ─► breach at the row
////              a row out of order or repeated          ─► breach at the row
//// ```
////
//// - The word is `Jim` with no letter, digit or underscore beside it, so
////   "Jimmy" and "prejim" are no breach, and "Jim's" is one.
//// - A row is `path text`: the file's path from the repository root, one
////   space, and the trimmed text of a line of that file. A line matches the
////   row by its trimmed text, so a line that moves stays kept, and a line
////   edited or removed leaves its row stale.
//// - A row is a stale breach, so the list holds no slack: fixing a line
////   deletes its row.
//// - The list is sorted by its rows, one row per line.
////
//// What the rule does not read: this module and its test (they name Jim to
//// state the rule), files that are not `.gleam`, `.erl`, `.py`, `.sh`, `.sql`,
//// `.css` or `.toml`, and `priv/`, `.claude/` and `CLAUDE.md`.

import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/bool
import gleam/list
import gleam/order
import gleam/string

/// A row of the keep list: the file, the trimmed text of a line it holds that
/// names Jim, and the row's line of the list file (from 1).
pub type Kept {
  Kept(path: String, text: String, line: Int)
}

/// The keep list.
pub const list_path = "test/code_rule/jim_source_keep.txt"

/// Files that state the rule and so name Jim.
const own_files = [
  "test/code_rule/jim_source.gleam", "test/code_rule/jim_source_test.gleam",
]

/// The list as its file writes it: `path text` on each line.
pub fn parse_list(text text: String) -> List(Kept) {
  text
  |> string.split("\n")
  |> list.index_map(fn(row, index) { #(row, index + 1) })
  |> list.filter(fn(entry) { string.trim(entry.0) != "" })
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let assert Ok(#(path, text)) = string.split_once(row, " ")
      as { "line " <> string.inspect(line) <> " of the list has no path" }
    Kept(path:, text:, line:)
  })
}

/// Each line naming Jim that no row holds, each row with no such line, and
/// each row out of order or repeated.
pub fn breaches(
  files files: List(SourceFile),
  kept kept: List(Kept),
) -> List(Breach) {
  let scanned =
    list.filter(files, fn(file) { !list.contains(own_files, file.path) })
  let named = list.map(scanned, fn(file) { #(file, naming_jim(file)) })
  let at_lines =
    list.flat_map(named, fn(entry) {
      let #(file, lines) = entry
      list.filter_map(lines, fn(found) {
        let #(line, text) = found
        case
          list.any(kept, fn(row) { row.path == file.path && row.text == text })
        {
          True -> Error(Nil)
          False ->
            Ok(Breach(
              path: file.path,
              line:,
              rule: "names Jim: state the source (a client address, a table row, a recording or the server's choice), or add the line to "
                <> list_path,
            ))
        }
      })
    })
  let at_rows =
    list.filter_map(kept, fn(row) {
      let holds =
        list.any(named, fn(entry) {
          let #(file, lines) = entry
          file.path == row.path
          && list.any(lines, fn(found) { found.1 == row.text })
        })
      case holds {
        True -> Error(Nil)
        False ->
          Ok(list_breach(
            row,
            "has no line naming Jim in its file: delete the row",
          ))
      }
    })
  list.flatten([at_lines, at_rows, disordered(kept)])
}

/// The line number and trimmed text of each line of the file naming Jim.
fn naming_jim(file: SourceFile) -> List(#(Int, String)) {
  use <- bool.guard(!string.contains(file.text, "Jim"), [])
  file.text
  |> string.split("\n")
  |> list.index_map(fn(line, index) { #(index + 1, string.trim(line)) })
  |> list.filter(fn(entry) { names_jim(entry.1) })
}

/// Whether the text holds the word Jim.
fn names_jim(text: String) -> Bool {
  let parts = string.split(text, "Jim")
  list.zip(parts, list.drop(parts, 1))
  |> list.any(fn(pair) {
    let #(before, after) = pair
    !ends_in_word(before) && !starts_in_word(after)
  })
}

fn ends_in_word(text: String) -> Bool {
  case list.last(string.to_graphemes(text)) {
    Ok(grapheme) -> in_word(grapheme)
    Error(Nil) -> False
  }
}

fn starts_in_word(text: String) -> Bool {
  case string.to_graphemes(text) {
    [grapheme, ..] -> in_word(grapheme)
    [] -> False
  }
}

fn in_word(grapheme: String) -> Bool {
  grapheme == "_"
  || string.contains(
    "abcdefghijklmnopqrstuvwxyz0123456789",
    string.lowercase(grapheme),
  )
}

/// A breach at each row that is not after the row before it.
fn disordered(kept: List(Kept)) -> List(Breach) {
  list.zip(kept, list.drop(kept, 1))
  |> list.filter_map(fn(pair) {
    let #(before, row) = pair
    case string.compare(key(before), key(row)) {
      order.Lt -> Error(Nil)
      order.Eq | order.Gt ->
        Ok(list_breach(
          row,
          "is out of order or repeated: keep one row per line, sorted",
        ))
    }
  })
}

fn key(row: Kept) -> String {
  row.path <> " " <> row.text
}

fn list_breach(row: Kept, what: String) -> Breach {
  Breach(path: list_path, line: row.line, rule: key(row) <> " " <> what)
}
