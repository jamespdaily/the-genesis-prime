//// The judged-count rule: a gate of a load run is judged through
//// `genesis_prime/load_judged`, so a gate cannot pass a run that measured nothing, and the
//// run's verdict is that module's alone.
////
//// ```
//// a load tool's file ─▶ the events its `Judged(event: ...)` calls name ─▶ each expected
////                       event missing from them is a breach, at the file's first line
//// a function that builds a `Judged` ─▶ every `Judged` is inside the `judged:` of a
////                       `load_judged.judge` whose result goes to `load_judged.require`
//// a string literal of the file ─▶ no verdict word, no event's name and a colon
//// ```
////
//// A string literal that holds a verdict word (`pass`, `fail` or `gate`, in any of their forms)
//// or begins an event's name and a colon is a verdict or a gate line printed by hand, which
//// is a breach, at its line.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list
import gleam/option.{Some}
import gleam/string

/// The breaches of a load tool's file: each of its `expected` events (variant names of
/// `load_judged.Event`) that no `Judged(event: ...)` of the file names, each function whose
/// `Judged` counts do not all reach `load_judged.require` through `load_judged.judge`, and
/// each string literal that prints a verdict by hand: one with a verdict word, or one that
/// begins an event's name from `printed`, then a colon.
pub fn breaches(
  file file: SourceFile,
  expected expected: List(String),
  conditions conditions: List(String),
  printed printed: List(String),
) -> List(Breach) {
  let _ = conditions
  let module = syntax.parse(file)
  let judged = judged_events(module)
  let not_judged =
    list.filter(expected, fn(event) { !list.contains(judged, event) })
    |> list.map(fn(event) {
      Breach(
        path: file.path,
        line: 1,
        rule: "a gate event is not judged through load_judged.Judged: " <> event,
      )
    })
  let by_hand =
    syntax.strings(module)
    |> list.filter(fn(literal) {
      list.any(printed, fn(name) { string.starts_with(literal.1, name <> ":") })
      || list.any(words(literal.1), verdict_word)
    })
    |> list.map(fn(literal) {
      Breach(
        path: file.path,
        line: syntax.line_of(text: file.text, byte_offset: literal.0),
        rule: "a verdict or gate line printed by hand, not through load_judged.judge",
      )
    })
  list.flatten([not_judged, unwired(file:, module:), by_hand])
}

/// The words of a text: its runs of letters, in lower case.
fn words(text: String) -> List(String) {
  string.lowercase(text)
  |> string.to_graphemes
  |> list.chunk(fn(letter) {
    string.contains("abcdefghijklmnopqrstuvwxyz", letter)
  })
  |> list.filter(fn(chunk) {
    list.all(chunk, fn(letter) {
      string.contains("abcdefghijklmnopqrstuvwxyz", letter)
    })
  })
  |> list.map(string.concat)
}

fn verdict_word(word: String) -> Bool {
  list.contains(
    [
      "pass", "passes", "passed", "passing", "fail", "fails", "failed",
      "failing", "failure", "gate", "gates",
    ],
    word,
  )
}

/// The breaches of the functions that build a `Judged`: one at the first `Judged` of a
/// function when any `Judged` of it is outside the `judged:` argument of a
/// `load_judged.judge` call, or when no `load_judged.require` call of it is given the
/// variable that a `let` of the function binds to a `load_judged.judge` call.
fn unwired(
  file file: SourceFile,
  module module: glance.Module,
) -> List(Breach) {
  list.flat_map(module.functions, fn(definition) {
    let calls = syntax.calls(glance.Module(..module, functions: [definition]))
    case list.filter(calls, is_judged) {
      [] -> []
      [first, ..] as judged_calls ->
        case
          all_inside_judge(judged_calls:, calls:)
          && is_required(
            calls:,
            verdicts: verdict_names(definition.definition.body),
          )
        {
          True -> []
          False -> [
            Breach(
              path: file.path,
              line: syntax.line_of(
                text: file.text,
                byte_offset: first.function.start,
              ),
              rule: "a Judged count does not reach load_judged.require through load_judged.judge",
            ),
          ]
        }
    }
  })
}

/// Whether each `Judged` call is written inside the `judged:` argument of a
/// `load_judged.judge` call.
fn all_inside_judge(
  judged_calls judged_calls: List(syntax.Call),
  calls calls: List(syntax.Call),
) -> Bool {
  let spans =
    list.filter(calls, called_through("judge"))
    |> list.filter_map(fn(call) { argument_span(call:, label: "judged") })
  list.all(judged_calls, fn(call) {
    list.any(spans, fn(span) {
      span.start <= call.function.start && call.function.end <= span.end
    })
  })
}

/// Whether a `load_judged.require` call is given a variable named in `verdicts`.
fn is_required(
  calls calls: List(syntax.Call),
  verdicts verdicts: List(String),
) -> Bool {
  list.filter(calls, called_through("require"))
  |> list.any(fn(call) {
    case
      syntax.argument(
        arguments: call.arguments,
        label: "verdict",
        position: syntax.FirstArgument,
      )
    {
      Some(glance.Variable(name:, ..)) -> list.contains(verdicts, name)
      _ -> False
    }
  })
}

fn argument_span(
  call call: syntax.Call,
  label label: String,
) -> Result(glance.Span, Nil) {
  case
    syntax.argument(
      arguments: call.arguments,
      label:,
      position: syntax.FirstArgument,
    )
  {
    Some(expression) -> Ok(syntax.span_of(expression))
    _ -> Error(Nil)
  }
}

/// The names that the function's own `let` statements bind to a `load_judged.judge` call.
fn verdict_names(body: List(glance.Statement)) -> List(String) {
  list.filter_map(body, fn(statement) {
    case statement {
      glance.Assignment(
        kind: glance.Let,
        pattern: glance.PatternVariable(name:, ..),
        value: glance.Call(
          function: glance.FieldAccess(
            container: glance.Variable(name: "load_judged", ..),
            label: "judge",
            ..,
          ),
          ..,
        ),
        ..,
      ) -> Ok(name)
      _ -> Error(Nil)
    }
  })
}

fn called_through(label: String) -> fn(syntax.Call) -> Bool {
  fn(call: syntax.Call) {
    case call.called {
      syntax.CalledThroughVariable(variable: "load_judged", label: found) ->
        found == label
      _ -> False
    }
  }
}

fn is_judged(call: syntax.Call) -> Bool {
  case call.called {
    syntax.CalledByName(name: "Judged")
    | syntax.CalledThroughVariable(label: "Judged", ..) -> True
    _ -> False
  }
}

/// The variant names the file's `Judged(event: ...)` calls give as the event.
fn judged_events(module: glance.Module) -> List(String) {
  syntax.calls(module)
  |> list.filter(is_judged)
  |> list.flat_map(fn(call) {
    list.filter_map(call.arguments, fn(argument) {
      case argument {
        glance.LabelledField(
          label: "event",
          item: glance.Variable(name:, ..),
          ..,
        )
        | glance.LabelledField(
            label: "event",
            item: glance.FieldAccess(label: name, ..),
            ..,
          ) -> Ok(name)
        _ -> Error(Nil)
      }
    })
  })
}
