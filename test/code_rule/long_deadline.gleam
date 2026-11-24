//// The long-deadline rule: a test's deadline above 10 000 ms names its measured
//// cause. A deadline given to `owned_test.run` (or `run_listed_in`,
//// `run_warning_to`, `run_under_salt`, by their `timeout_ms`) above the limit is
//// refused unless a comment on the line above names where the time goes, or the
//// test is on the list of the long deadlines that stood when the rule was made.
//// Two raised deadlines of 120 s with no cause, one for a file that ran in 2 s,
//// are what it stops.
////
//// ```
//// test file ──► each call of owned_test's runner ──► its deadline, read as an
////                                                    integer literal
////                       │                                 │ above 10 000 ms
////                       ▼                                 ▼
////    not a literal ─► breach              `// deadline:` comment above it?
////                                          yes ─► passes  no ─► on the list?
////                                                       yes, at or under its
////                                                       ceiling ─► passes
////                                                       no, or over ─► breach
//// the list ──► a listed test with no deadline above the limit, or one that names
////              its cause as well, is a breach at its line of the list
//// ```
////
//// - The cause is a comment block directly above the call (no blank line, no
////   code between) with a line that starts `// deadline:` followed by words
////   that hold a number: the measured run time. Lines of the block after that
////   line go on with the cause.
//// - The list (`list_path`) holds one `module test ceiling_ms` line per test
////   (the module as `syntax.module_name` writes it), sorted. Its entries only
////   come off: a test whose cause is written, or whose deadline is cut to the
////   limit or below, leaves it, and the rule fails while it stays. A listed test's
////   deadline may be lowered and stay long; it may not go above its ceiling.
//// - A deadline the rule cannot read is a breach: a variable, a constant, a
////   punned `timeout_ms:`, or the runner taken as a value. The call must carry
////   the integer, so the rule sees the number the test runs by.
////
//// What the rule does not read: a deadline a helper of a test module passes on to
//// `owned_test.run`, since the helper's own call is the one read.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A test on the list: its module (as `syntax.module_name` writes it), its
/// function, the deadline it may not go above, and its line of the list file
/// (counted from 1).
pub type Listed {
  Listed(module: String, test_name: String, ceiling_ms: Int, line: Int)
}

/// The list of the long deadlines that stood when the rule was made.
pub const list_path = "test/code_rule/long_deadlines.txt"

/// A deadline above this is long.
const limit_ms = 10_000

/// The functions of `owned_test` that take a test's deadline.
const runners = ["run", "run_listed_in", "run_warning_to", "run_under_salt"]

/// The label the runners give the deadline.
const deadline_label = "timeout_ms"

const cause_prefix = "// deadline:"

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

/// One call of the runner: the function it is in, where it is written, and the
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

/// Each long deadline with no cause that the list does not cover, each deadline
/// the rule cannot read, and each listed test that has no deadline above the
/// limit, goes over its ceiling or names its cause as well.
pub fn breaches(
  files files: List(SourceFile),
  listed listed: List(Listed),
) -> List(Breach) {
  let calls = list.flat_map(files, calls_of)
  let listed_by_test =
    list.map(listed, fn(entry) { #(#(entry.module, entry.test_name), entry) })
    |> dict.from_list
  let long_by_test =
    calls
    |> list.filter(is_long)
    |> list.group(fn(call) { #(call.module, call.function) })
  let at_calls =
    list.filter_map(calls, fn(call) {
      case call.deadline_ms {
        Error(Nil) ->
          Ok(Breach(
            path: call.path,
            line: call.line,
            rule: "a test deadline that is not an integer literal, which the rule cannot read",
          ))
        Ok(deadline_ms) -> at_call(call:, deadline_ms:, listed: listed_by_test)
      }
    })
  let at_list =
    list.filter_map(listed, fn(entry) {
      let long =
        dict.get(long_by_test, #(entry.module, entry.test_name))
        |> result.unwrap([])
      case long {
        [] ->
          Ok(list_breach(
            entry,
            "is listed and has no deadline above "
              <> int.to_string(limit_ms)
              <> " ms: take it off the list",
          ))
        _ ->
          case list.any(long, fn(call) { call.cause }) {
            True ->
              Ok(list_breach(
                entry,
                "is listed and names its cause: take it off the list",
              ))
            False -> Error(Nil)
          }
      }
    })
  list.append(at_calls, at_list)
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
          <> " ms",
      ))
    True, False, Error(Nil) ->
      Ok(Breach(
        path: call.path,
        line: call.line,
        rule: "a test deadline above "
          <> int.to_string(limit_ms)
          <> " ms with no `"
          <> cause_prefix
          <> "` comment above it that names its measured run time",
      ))
  }
}

fn is_long(call: Call) -> Bool {
  case call.deadline_ms {
    Ok(deadline_ms) -> deadline_ms > limit_ms
    Error(Nil) -> False
  }
}

fn list_breach(entry: Listed, what: String) -> Breach {
  Breach(
    path: list_path,
    line: entry.line,
    rule: entry.module <> " " <> entry.test_name <> " " <> what,
  )
}

/// Every call of the runner in the file, in the order written.
fn calls_of(file: SourceFile) -> List(Call) {
  let module = syntax.parse(file)
  let calls = arguments_by_start(syntax.expressions(module))
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
        deadline_ms: deadline_of(calls, start),
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

/// The arguments of each call in the module, by where its function starts.
fn arguments_by_start(
  expressions: List(glance.Expression),
) -> Dict(Int, List(glance.Field(glance.Expression))) {
  list.filter_map(expressions, fn(expression) {
    case expression {
      glance.Call(function:, arguments:, ..) ->
        Ok(#(syntax.span_of(function).start, arguments))
      glance.Int(..)
      | glance.Float(..)
      | glance.String(..)
      | glance.Variable(..)
      | glance.NegateInt(..)
      | glance.NegateBool(..)
      | glance.Block(..)
      | glance.Panic(..)
      | glance.Todo(..)
      | glance.Tuple(..)
      | glance.List(..)
      | glance.Fn(..)
      | glance.RecordUpdate(..)
      | glance.FieldAccess(..)
      | glance.TupleIndex(..)
      | glance.FnCapture(..)
      | glance.BitString(..)
      | glance.Case(..)
      | glance.BinaryOperator(..)
      | glance.Echo(..) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// The integer literal a call gives as its deadline: its `timeout_ms:`
/// argument, or else its first unlabelled one. A reference that is not the
/// function of a call has none.
fn deadline_of(
  calls: Dict(Int, List(glance.Field(glance.Expression))),
  start: Int,
) -> Result(Int, Nil) {
  use arguments <- result.try(dict.get(calls, start))
  case deadline_argument(arguments) {
    Some(glance.Int(value:, ..)) ->
      value |> string.replace("_", "") |> int.parse
    Some(_) | None -> Error(Nil)
  }
}

fn deadline_argument(
  arguments: List(glance.Field(glance.Expression)),
) -> Option(glance.Expression) {
  let labelled =
    list.find_map(arguments, fn(argument) {
      case argument {
        glance.LabelledField(label:, item:, ..) if label == deadline_label ->
          Ok(Some(item))
        glance.ShorthandField(label:, ..) if label == deadline_label -> Ok(None)
        glance.LabelledField(..)
        | glance.ShorthandField(..)
        | glance.UnlabelledField(..) -> Error(Nil)
      }
    })
  case labelled {
    Ok(found) -> found
    Error(Nil) ->
      list.find_map(arguments, fn(argument) {
        case argument {
          glance.UnlabelledField(item) -> Ok(item)
          glance.LabelledField(..) | glance.ShorthandField(..) -> Error(Nil)
        }
      })
      |> option.from_result
  }
}

/// Whether the comment block directly above the line (1-based) has a line that
/// starts with the cause prefix, and that line with the block lines after it
/// holds a number.
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
    [first, ..rest] -> {
      let words =
        [string.remove_prefix(first, cause_prefix), ..rest]
        |> string.join(" ")
      list.any(string.to_graphemes("0123456789"), fn(digit) {
        string.contains(words, digit)
      })
    }
  }
}
