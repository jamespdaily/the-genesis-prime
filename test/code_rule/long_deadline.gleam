//// The long-deadline rule: a test's deadline above 10 000 ms names its measured
//// cause. A deadline given to one of `owned_test`'s runners (each public
//// function that takes a `timeout_ms`) above the limit is refused unless a
//// comment on the line above names where the time goes, or the test is on the
//// list of long deadlines that have no cause, each with the deadline it may not
//// go above.
////
//// ```
//// test file ──► each call of a runner ──► its deadline, read as an integer
////                                          literal
////                       │                        │ above 10 000 ms
////                       ▼                        ▼
////    not a literal ─► breach          `// deadline:` comment above it?
////                                       yes ─► passes   no ─► on the list?
////                                                    yes, at or under its
////                                                    ceiling ─► passes
////                                                    no, or over ─► breach
//// the list ──► more rows than `most_rows`, or rows out of order or repeated,
////              are breaches at the list's lines
//// ```
////
//// - The runners are read from `test/owned_test.gleam`, so a runner added there
////   is read with no change here.
//// - The cause is a comment block directly above the call (no blank line, no
////   code between) with a line that starts `// deadline:` followed by words
////   that hold a time with its unit (`12 s`, `300ms`): the measured run time.
////   Lines of the block after that line go on with the cause.
//// - The list (`list_path`) holds one `module test ceiling_ms` line per test
////   (the module as `syntax.module_name` writes it), sorted, one row per test.
////   It holds at most `most_rows` rows, so it cannot grow: a new long deadline
////   names its cause. A row for a test that is gone, renamed or no longer long
////   does nothing, and a listed test's deadline may be lowered and stay long;
////   it may not go above its ceiling.
//// - A deadline the rule cannot read is a breach: a variable, a constant, a
////   punned `timeout_ms:`, or the runner taken as a value. The call must carry
////   the integer, so the rule sees the number the test runs by.
////
//// What the rule does not read: a deadline a helper of a test module passes on to
//// a runner, since the helper's own call is the one read.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string

/// A test on the list: its module (as `syntax.module_name` writes it), its
/// function, the deadline it may not go above, and its line of the list file
/// (counted from 1).
pub type Listed {
  Listed(module: String, test_name: String, ceiling_ms: Int, line: Int)
}

/// The list of long deadlines that have no cause.
pub const list_path = "test/code_rule/long_deadlines.txt"

/// The most rows the list may hold. A new long deadline names its cause rather
/// than raising this; cutting a deadline lowers it.
pub const most_rows = 2616

/// A deadline above this is long.
const limit_ms = 10_000

/// The label the runners give the deadline.
const deadline_label = "timeout_ms"

const cause_prefix = "// deadline:"

/// The words that end a number as a time: `12 s`, `300ms`, `2 minutes`.
const time_units = ["ms", "s", "sec", "seconds", "min", "minutes"]

/// The runners: each public function of `owned_test`'s file that takes a
/// `timeout_ms`, by label or by name, sorted by name.
pub fn runners_of(file: SourceFile) -> List(String) {
  syntax.parse(file).functions
  |> list.map(fn(definition) { definition.definition })
  |> list.filter(fn(function) {
    function.publicity == glance.Public
    && list.any(function.parameters, takes_deadline)
  })
  |> list.map(fn(function) { function.name })
  |> list.sort(string.compare)
}

fn takes_deadline(parameter: glance.FunctionParameter) -> Bool {
  parameter.label == Some(deadline_label)
  || parameter.name == glance.Named(deadline_label)
}

/// The list as its file writes it: `module test ceiling_ms` on each line.
pub fn parse_list(text text: String) -> List(Listed) {
  text
  |> string.split("\n")
  |> list.index_map(fn(row, index) { #(row, index + 1) })
  |> list.filter(fn(entry) { string.trim(entry.0) != "" })
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let assert [module, test_name, ceiling] =
      string.split(string.trim(row), " ")
      as { "line " <> int.to_string(line) <> " of the list is not three words" }
    let assert Ok(ceiling_ms) = int.parse(ceiling)
      as { "line " <> int.to_string(line) <> " of the list has no ceiling" }
    Listed(module:, test_name:, ceiling_ms:, line:)
  })
}

/// One call of a runner: the function it is in, where it is written, and the
/// deadline it gives (an error when it is not an integer literal).
type Call {
  Call(
    module: String,
    function: String,
    path: String,
    line: Int,
    deadline_ms: Result(Int, Nil),
    cause: Bool,
  )
}

/// Each long deadline with no cause that the list does not cover, each listed
/// deadline raised above its ceiling, each deadline the rule cannot read, and
/// the faults of the list itself: more than `most_rows` rows, or a row that is
/// not after the one before it in module and test order.
pub fn breaches(
  files files: List(SourceFile),
  runners runners: List(String),
  listed listed: List(Listed),
  most_rows most_rows: Int,
) -> List(Breach) {
  let listed_by_test =
    list.map(listed, fn(entry) { #(#(entry.module, entry.test_name), entry) })
    |> dict.from_list
  let at_calls =
    files
    |> list.flat_map(calls_of(_, runners))
    |> list.filter_map(fn(call) {
      case call.deadline_ms {
        Error(Nil) ->
          Ok(Breach(
            path: call.path,
            line: call.line,
            rule: "a test deadline that is not an integer literal given as the first argument or as `"
              <> deadline_label
              <> ":`, which the rule cannot read",
          ))
        Ok(deadline_ms) -> at_call(call:, deadline_ms:, listed: listed_by_test)
      }
    })
  list.append(at_calls, list_breaches(listed:, most_rows:))
}

fn at_call(
  call call: Call,
  deadline_ms deadline_ms: Int,
  listed listed: Dict(#(String, String), Listed),
) -> Result(Breach, Nil) {
  let entry = dict.get(listed, #(call.module, call.function))
  case deadline_ms > limit_ms, call.cause, entry {
    False, _, _ -> Error(Nil)
    True, True, _ -> Error(Nil)
    True, False, Ok(entry) if deadline_ms <= entry.ceiling_ms -> Error(Nil)
    True, False, Ok(entry) ->
      Ok(Breach(
        path: call.path,
        line: call.line,
        rule: "a test deadline of "
          <> int.to_string(deadline_ms)
          <> " ms above its listed ceiling of "
          <> int.to_string(entry.ceiling_ms)
          <> " ms: write the cause above the call, as `"
          <> cause_prefix
          <> " <measured run time, such as 12 s, and why>`",
      ))
    True, False, Error(Nil) ->
      Ok(Breach(
        path: call.path,
        line: call.line,
        rule: "a test deadline above "
          <> int.to_string(limit_ms)
          <> " ms with no cause: write `"
          <> cause_prefix
          <> " <measured run time, such as 12 s, and why>` on the line above the call, or cut the deadline to "
          <> int.to_string(limit_ms)
          <> " ms or less",
      ))
  }
}

/// A breach at the last row when the list holds more than `most_rows`, and one
/// at each row that is not after the row before it.
fn list_breaches(
  listed listed: List(Listed),
  most_rows most_rows: Int,
) -> List(Breach) {
  let too_many = case list.length(listed) > most_rows, list.last(listed) {
    True, Ok(last) -> [
      list_breach(
        last,
        "is past the "
          <> int.to_string(most_rows)
          <> " rows the list may hold: name the cause of the long deadline with a `"
          <> cause_prefix
          <> "` comment instead of listing it",
      ),
    ]
    True, Error(Nil) | False, _ -> []
  }
  let disordered =
    list.zip(listed, list.drop(listed, 1))
    |> list.filter_map(fn(pair) {
      let #(before, row) = pair
      case compare_rows(before, row) {
        order.Lt -> Error(Nil)
        order.Eq | order.Gt ->
          Ok(list_breach(
            row,
            "is out of order or repeated: keep one row per test, sorted by module and then test",
          ))
      }
    })
  list.append(too_many, disordered)
}

fn compare_rows(first: Listed, second: Listed) -> order.Order {
  string.compare(first.module, second.module)
  |> order.break_tie(string.compare(first.test_name, second.test_name))
}

fn list_breach(entry: Listed, what: String) -> Breach {
  Breach(
    path: list_path,
    line: entry.line,
    rule: entry.module <> " " <> entry.test_name <> " " <> what,
  )
}

/// Every call of a runner in the file, in the order written.
fn calls_of(file: SourceFile, runners: List(String)) -> List(Call) {
  let module = syntax.parse(file)
  let arguments_by_start =
    syntax.calls(module)
    |> list.map(fn(call) { #(call.function.start, call.arguments) })
    |> dict.from_list
  let functions =
    module.functions
    |> list.map(fn(definition) {
      #(definition.definition.location.start, definition.definition.name)
    })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  let lines = string.split(file.text, "\n")
  let starts =
    syntax.references_to(module:, from: ["owned_test"], named: runners)
    |> list.map(fn(reference) { syntax.location_of(reference).start })
  list.map2(
    starts,
    syntax.lines_of(text: file.text, byte_offsets: starts),
    fn(start, line) {
      Call(
        module: syntax.module_name(file.path),
        function: enclosing(functions, start),
        path: file.path,
        line:,
        deadline_ms: deadline_of(arguments_by_start, start),
        cause: names_its_cause(lines, line),
      )
    },
  )
}

/// The function whose declaration is the last one that starts at or before the
/// offset.
fn enclosing(functions: List(#(Int, String)), offset: Int) -> String {
  functions
  |> list.filter(fn(function) { function.0 <= offset })
  |> list.last
  |> result.map(fn(function) { function.1 })
  |> result.unwrap("")
}

/// The integer literal a call gives as its deadline: its `timeout_ms:`
/// argument, or else its first argument when that has no label. A reference
/// that is not the function of a call has none.
fn deadline_of(
  arguments_by_start: Dict(Int, List(glance.Field(glance.Expression))),
  start: Int,
) -> Result(Int, Nil) {
  use arguments <- result.try(dict.get(arguments_by_start, start))
  let deadline: Option(glance.Expression) =
    syntax.argument(
      arguments,
      label: deadline_label,
      position: syntax.FirstArgument,
    )
  case deadline {
    Some(glance.Int(value:, ..)) ->
      value |> string.replace("_", "") |> int.parse
    Some(_) | None -> Error(Nil)
  }
}

/// Whether the comment block directly above the line (1-based) has a line that
/// starts with the cause prefix, and that line with the block lines after it
/// holds a time with its unit.
fn names_its_cause(lines: List(String), line: Int) -> Bool {
  let block =
    lines
    |> list.take(line - 1)
    |> list.reverse
    |> list.take_while(fn(row) { string.starts_with(string.trim(row), "//") })
    |> list.map(string.trim)
    |> list.reverse
  case
    list.drop_while(block, fn(row) { !string.starts_with(row, cause_prefix) })
  {
    [] -> False
    [first, ..rest] ->
      [string.remove_prefix(first, cause_prefix), ..rest]
      |> string.join(" ")
      |> string.to_graphemes
      |> holds_a_time
  }
}

/// Whether a number is followed, after any spaces, by one of the time units.
fn holds_a_time(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> False
    [first, ..rest] ->
      case is_digit(first) {
        False -> holds_a_time(rest)
        True -> {
          let after =
            list.drop_while(graphemes, fn(grapheme) {
              is_digit(grapheme) || grapheme == "."
            })
          let unit =
            after
            |> list.drop_while(fn(grapheme) { grapheme == " " })
            |> list.take_while(is_letter)
            |> string.concat
          list.contains(time_units, unit) || holds_a_time(after)
        }
      }
  }
}

fn is_digit(grapheme: String) -> Bool {
  string.contains("0123456789", grapheme)
}

fn is_letter(grapheme: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyz", grapheme)
}
