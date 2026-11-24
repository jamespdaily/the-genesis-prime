//// A test looks at an eventual state only inside `event_wait.until`. A
//// monitor a process sets, a message it takes from its mailbox, a port that
//// closes: each becomes true some time after the event the test last saw, so
//// an assert on it at that moment passes or fails by timing. The probes read
//// such a state (`mailbox_support`'s `monitored`, `queued`, `tagged`,
//// `tagged_by_reference` and `call_waiting_from`, and `login_client.refused`),
//// and a call of one is a breach unless it sits inside a closure given to
//// `event_wait.until`, which looks again until the state holds.
////
//// Two probes are no breach outside a wait, since their state is not eventual:
//// a probe of the test's own mailbox (`process.self()`: a message the test sent
//// itself is in it when the send returns), and a probe of a process
//// `mailbox_support.settled` returned (it has taken what it was sent, so a
//// regression fails at once and the assert does not depend on timing).
////
//// A probe in a helper is a breach too: the helper cannot tell whether its
//// caller waits, so the helper takes the wait inside itself.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// The modules the probes belong to, and the probes of each.
const probes = [
  #("mailbox_support", [
    "monitored", "queued", "tagged", "tagged_by_reference", "call_waiting_from",
  ]),
  #("login_client", ["refused"]),
]

/// Each call of a probe in the file that is outside every closure given to
/// `event_wait.until`, at the line of the probe. A probe of `process.self()` or
/// of a `mailbox_support.settled` process is left out.
pub fn breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  let calls = syntax.calls(module)
  let waits = waiting_closures(module, calls)
  let exempt = probes_of_settled_state(module, calls)
  list.flat_map(probes, fn(probe) {
    let #(from, named) = probe
    syntax.references_to(module:, from: [from], named:)
  })
  |> list.map(syntax.location_of)
  |> list.filter(fn(location) {
    !list.any(waits, contains(_, location)) && !list.contains(exempt, location)
  })
  |> list.map(fn(location) {
    Breach(
      path: file.path,
      line: syntax.line_of(file.text, location.start),
      rule: "a probe of an eventual state outside a closure given to `event_wait.until`",
    )
  })
  |> list.sort(fn(first, second) { int.compare(first.line, second.line) })
}

/// The span of each closure that is an argument of a call of `event_wait.until`.
fn waiting_closures(
  module: glance.Module,
  calls: List(syntax.Call),
) -> List(glance.Span) {
  let until_locations =
    syntax.references_to(module:, from: ["event_wait"], named: ["until"])
    |> list.map(syntax.location_of)
  list.flat_map(calls, fn(call) {
    case list.contains(until_locations, call.function) {
      True -> closures(call.arguments)
      False -> []
    }
  })
}

/// Where the function of each call is written whose first argument is a call of
/// `process.self` or of `mailbox_support.settled`.
fn probes_of_settled_state(
  module: glance.Module,
  calls: List(syntax.Call),
) -> List(glance.Span) {
  let settled_locations =
    list.append(
      syntax.references_to(module:, from: ["mailbox_support"], named: [
        "settled",
      ]),
      syntax.references_to(module:, from: ["gleam/erlang/process"], named: [
        "self",
      ]),
    )
    |> list.map(syntax.location_of)
  list.filter_map(calls, fn(call) {
    case call.arguments {
      [first, ..] ->
        case called_function(first) {
          Some(function) ->
            case list.contains(settled_locations, function) {
              True -> Ok(call.function)
              False -> Error(Nil)
            }
          None -> Error(Nil)
        }
      [] -> Error(Nil)
    }
  })
}

/// Where the function is written when the argument is a call.
fn called_function(
  argument: glance.Field(glance.Expression),
) -> Option(glance.Span) {
  case argument {
    glance.LabelledField(item: glance.Call(function:, ..), ..)
    | glance.UnlabelledField(glance.Call(function:, ..)) ->
      Some(syntax.span_of(function))
    glance.LabelledField(..)
    | glance.UnlabelledField(..)
    | glance.ShorthandField(..) -> None
  }
}

fn closures(
  arguments: List(glance.Field(glance.Expression)),
) -> List(glance.Span) {
  list.filter_map(arguments, fn(argument) {
    case argument {
      glance.LabelledField(item: glance.Fn(location:, ..), ..)
      | glance.UnlabelledField(glance.Fn(location:, ..)) -> Ok(location)
      glance.LabelledField(..)
      | glance.UnlabelledField(..)
      | glance.ShorthandField(..) -> Error(Nil)
    }
  })
}

fn contains(outer: glance.Span, inner: glance.Span) -> Bool {
  outer.start <= inner.start && inner.end <= outer.end
}
