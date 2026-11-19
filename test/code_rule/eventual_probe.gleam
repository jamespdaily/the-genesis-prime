//// A test looks at an eventual state only inside `event_wait.until`. A
//// monitor a process sets, a message it takes from its mailbox, a port that
//// closes: each becomes true some time after the event the test last saw, so
//// an assert on it at that moment passes or fails by timing. The probes read
//// such a state (`mailbox_support`'s `monitored`, `queued`, `tagged`,
//// `tagged_by_reference` and `call_waiting_from`, and `login_client.refused`),
//// and a call of one is a breach unless it sits inside a closure given to
//// `event_wait.until`, which looks again until the state holds.
////
//// A probe in a helper is a breach too: the helper cannot tell whether its
//// caller waits, so the helper takes the wait inside itself.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/int
import gleam/list

/// The modules the probes belong to, and the probes of each.
const probes = [
  #("mailbox_support", [
    "monitored", "queued", "tagged", "tagged_by_reference", "call_waiting_from",
  ]),
  #("login_client", ["refused"]),
]

/// Each call of a probe in the file that is outside every closure given to
/// `event_wait.until`, at the line of the probe.
pub fn breaches(file: SourceFile) -> List(Breach) {
  let module = syntax.parse(file)
  let waits = waiting_closures(module)
  list.flat_map(probes, fn(probe) {
    let #(from, named) = probe
    syntax.references_to(module:, from: [from], named:)
  })
  |> list.map(syntax.location_of)
  |> list.filter(fn(location) { !list.any(waits, contains(_, location)) })
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
fn waiting_closures(module: glance.Module) -> List(glance.Span) {
  let until_locations =
    syntax.references_to(module:, from: ["event_wait"], named: ["until"])
    |> list.map(syntax.location_of)
  list.flat_map(syntax.expressions(module), fn(expression) {
    case expression {
      glance.Call(function:, arguments:, ..) ->
        case list.contains(until_locations, location_of(function)) {
          True -> closures(arguments)
          False -> []
        }
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
      | glance.Echo(..) -> []
    }
  })
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

fn location_of(expression: glance.Expression) -> glance.Span {
  case expression {
    glance.FieldAccess(location:, ..) -> location
    glance.Int(location:, ..)
    | glance.Float(location:, ..)
    | glance.String(location:, ..)
    | glance.Variable(location:, ..)
    | glance.NegateInt(location:, ..)
    | glance.NegateBool(location:, ..)
    | glance.Block(location:, ..)
    | glance.Panic(location:, ..)
    | glance.Todo(location:, ..)
    | glance.Tuple(location:, ..)
    | glance.List(location:, ..)
    | glance.Fn(location:, ..)
    | glance.RecordUpdate(location:, ..)
    | glance.Call(location:, ..)
    | glance.TupleIndex(location:, ..)
    | glance.FnCapture(location:, ..)
    | glance.BitString(location:, ..)
    | glance.Case(location:, ..)
    | glance.BinaryOperator(location:, ..)
    | glance.Echo(location:, ..) -> location
  }
}

fn contains(outer: glance.Span, inner: glance.Span) -> Bool {
  outer.start <= inner.start && inner.end <= outer.end
}
