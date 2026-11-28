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
//// What the rule does not read: this module, its test and its list (they name
//// Jim to state the rule), files that are not text, and files outside `src/`,
//// `test/` and `dev/`.

import code_rule/list_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import gleam/bool
import gleam/list
import gleam/string

/// A row of the keep list: the file, the trimmed text of a line it holds that
/// names Jim, and the row's line of the list file (from 1).
pub type Kept {
  Kept(path: String, text: String, line: Int)
}

/// The keep list.
pub const list_path = "test/code_rule/jim_source_keep.txt"

/// Files that state the rule and so name Jim; the list file holds the kept
/// lines, so it names Jim too.
const own_files = [
  "test/code_rule/jim_source.gleam", "test/code_rule/jim_source_test.gleam",
  list_path,
]

/// The list as its file writes it: `path text` on each line.
pub fn parse_list(text text: String) -> List(Kept) {
  list_file.rows(text)
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let assert Ok(#(path, text)) = string.split_once(row, " ")
      as list_file.bad_row(line:, what: "has no path")
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
          Ok(list_file.breach(
            path: list_path,
            line: row.line,
            name: key(row),
            what: "has no line naming Jim in its file: delete the row",
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

fn disordered(kept: List(Kept)) -> List(Breach) {
  list_file.disordered(
    rows: kept,
    compare: fn(before, row) { string.compare(key(before), key(row)) },
    path: list_path,
    line: fn(row) { row.line },
    name: key,
    what: "is out of order or repeated: keep one row per line, sorted",
  )
}

fn key(row: Kept) -> String {
  row.path <> " " <> row.text
}
