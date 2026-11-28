//// The let-assert rule: every `let assert` in `src/` and `dev/` carries a
//// message that states why it cannot fail, and no module holds more of them
//// than its row of the ceiling list.
////
//// ```
//// each file ──► its `let assert` statements (`syntax.let_asserts`)
////                 │ no `as`, or `as ""`          ─► breach at the statement
////                 │ more than the module's row   ─► breach at the first one
////                 │                                 past the row, by line
////                 │ fewer than the row           ─► breach at the row's line
//// the list ──► a row for a module that holds none or below 1, a row out of
////              order or repeated, or a count of rows other than `most_rows`
////              ─► breach at the row
//// ```
////
//// - The list (`list_path`) holds one `module ceiling` line per module that
////   holds a `let assert` (the module as `syntax.module_name` writes it, so a
////   `dev/` module reads `dev/game_client`), sorted. A module with no row has
////   a ceiling of 0.
//// - A row equals its module's count, so a ceiling never stays above the count
////   as slack for a new assert: cutting an assert lowers its row.
//// - The list holds exactly `most_rows` rows, so a new module cannot join it
////   without an existing row going, and a gone row leaves no slack. A module
////   split off one that holds some raises `most_rows` by one in the same
////   change, and review checks that the moved count matches.
//// - A row that is not two words, or whose ceiling is not an integer, stops
////   the test naming its line; no planted case can show that.
////
//// What the rule does not read: whether a message is true (review does), plain
//// `assert`, `panic` and `.erl` files.

import code_rule/list_file
import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/string

/// A module on the list: its name as `syntax.module_name` writes it, the
/// number of `let assert` it holds, and its line of the list file (from 1).
pub type Listed {
  Listed(module: String, ceiling: Int, line: Int)
}

/// The list of ceilings.
pub const list_path = "test/code_rule/let_assert_ceilings.txt"

/// The number of rows the list holds: cutting a module's last assert deletes
/// its row and lowers this by one.
pub const most_rows = 116

/// The list as its file writes it: `module ceiling` on each line.
pub fn parse_list(text text: String) -> List(Listed) {
  list_file.pairs(text:, what: "is not two words")
  |> list.map(fn(entry) {
    let #(module, ceiling, line) = entry
    let assert Ok(ceiling) = int.parse(ceiling)
      as list_file.bad_row(line:, what: "has no ceiling")
    Listed(module:, ceiling:, line:)
  })
}

/// A `let assert` of a file and its line.
type Found {
  Found(statement: syntax.LetAssert, line: Int)
}

/// Each `let assert` with no message or an empty one, each module past its
/// ceiling, each row above its module's count, and the faults of the list
/// itself.
pub fn breaches(
  files files: List(SourceFile),
  listed listed: List(Listed),
  most_rows most_rows: Int,
) -> List(Breach) {
  let ceilings =
    listed
    |> list.map(fn(entry) { #(entry.module, entry.ceiling) })
    |> dict.from_list
  let found = list.map(files, fn(file) { #(file, found_in(file)) })
  let counts =
    found
    |> list.map(fn(entry) {
      #(syntax.module_name({ entry.0 }.path), list.length(entry.1))
    })
    |> dict.from_list
  let at_files =
    list.flat_map(found, fn(entry) {
      let #(file, asserts) = entry
      let ceiling =
        dict.get(ceilings, syntax.module_name(file.path))
        |> result.unwrap(0)
      list.append(
        list.filter_map(asserts, message_breach(file, _)),
        over_ceiling(file:, asserts:, ceiling:),
      )
    })
  let at_rows =
    list.filter_map(listed, fn(entry) {
      let count = dict.get(counts, entry.module) |> result.unwrap(0)
      case entry.ceiling < 1, count < entry.ceiling {
        True, _ -> Ok(no_ceiling(entry))
        False, True -> Ok(below_row(entry, count))
        False, False -> Error(Nil)
      }
    })
  list.flatten([at_files, at_rows, list_breaches(listed:, most_rows:)])
}

fn found_in(file: SourceFile) -> List(Found) {
  let statements = syntax.let_asserts(syntax.parse(file))
  let lines =
    syntax.lines_of(
      text: file.text,
      byte_offsets: list.map(statements, fn(statement) { statement.start }),
    )
  list.map2(statements, lines, fn(statement, line) { Found(statement:, line:) })
  |> list.sort(fn(a, b) { int.compare(a.line, b.line) })
}

fn message_breach(file: SourceFile, found: Found) -> Result(Breach, Nil) {
  case found.statement.message {
    Some(glance.String(value: "", ..)) ->
      Ok(Breach(
        path: file.path,
        line: found.line,
        rule: "a `let assert` with an empty message: state why it cannot fail",
      ))
    Some(_) -> Error(Nil)
    None ->
      Ok(Breach(
        path: file.path,
        line: found.line,
        rule: "a `let assert` with no message: add `as \"<why it cannot fail>\"`",
      ))
  }
}

/// One breach at the first assert past the ceiling, when the file holds more
/// than the ceiling.
fn over_ceiling(
  file file: SourceFile,
  asserts asserts: List(Found),
  ceiling ceiling: Int,
) -> List(Breach) {
  case list.drop(asserts, ceiling) {
    [] -> []
    [first, ..] -> [
      Breach(
        path: file.path,
        line: first.line,
        rule: "past the module's ceiling of "
          <> int.to_string(ceiling)
          <> " `let assert` ("
          <> list_path
          <> "): handle the case instead of adding one",
      ),
    ]
  }
}

fn no_ceiling(entry: Listed) -> Breach {
  list_file.breach(
    path: list_path,
    line: entry.line,
    name: entry.module,
    what: "has a ceiling of "
      <> int.to_string(entry.ceiling)
      <> ": write the module's count of `let assert`, or delete the row when it holds none",
  )
}

fn below_row(entry: Listed, count: Int) -> Breach {
  let fix = case count {
    0 -> "delete the row"
    _ -> "write " <> int.to_string(count)
  }
  list_file.breach(
    path: list_path,
    line: entry.line,
    name: entry.module,
    what: "holds "
      <> int.to_string(count)
      <> " `let assert`, below its row of "
      <> int.to_string(entry.ceiling)
      <> ": "
      <> fix
      <> ", so the row is no slack for a new one",
  )
}

/// A breach at the last row when the list holds more than `most_rows`, and one
/// at each row that is not after the row before it.
fn list_breaches(
  listed listed: List(Listed),
  most_rows most_rows: Int,
) -> List(Breach) {
  let rows = list.length(listed)
  let wrong_count = case int.compare(rows, most_rows), list.last(listed) {
    order.Gt, Ok(last) -> [
      list_file.breach(
        path: list_path,
        line: last.line,
        name: last.module,
        what: "is past the "
          <> int.to_string(most_rows)
          <> " rows the list may hold: a new module cannot add a `let assert`;"
          <> " a module split off one that holds some raises `most_rows` by one"
          <> " in the same change, and review checks the moved count",
      ),
    ]
    order.Lt, Ok(last) -> [
      list_file.breach(
        path: list_path,
        line: last.line,
        name: last.module,
        what: "is the last of "
          <> int.to_string(rows)
          <> " rows, under the "
          <> int.to_string(most_rows)
          <> " the list may hold: lower `most_rows` to "
          <> int.to_string(rows)
          <> ", so a gone row is no slack for a new module",
      ),
    ]
    order.Gt, Error(Nil) | order.Lt, Error(Nil) | order.Eq, _ -> []
  }
  let disordered =
    list_file.disordered(
      rows: listed,
      compare: fn(before, row) { string.compare(before.module, row.module) },
      path: list_path,
      line: fn(row) { row.line },
      name: fn(row) { row.module },
      what: "is out of order or repeated: keep one row per module, sorted",
    )
  list.append(wrong_count, disordered)
}
