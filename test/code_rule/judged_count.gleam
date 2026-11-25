//// The judged-count rule: a gate event of a load run is judged through
//// `genesis_prime/load_judged`, so a gate cannot pass a run that measured nothing.
////
//// ```
//// a load tool's file ─▶ the events its `Judged(event: ...)` calls name ─▶ each expected
////                       event missing from them is a breach, at the file's first line
//// ```
////
//// A string literal that begins an event's name and a colon is the line of a count that
//// the file printed by hand, which is also a breach, at its line.

import code_rule/source.{type Breach, type SourceFile, Breach}
import code_rule/syntax
import glance
import gleam/list
import gleam/string

/// The breaches of a load tool's file: each of its `expected` events (variant names of
/// `load_judged.Event`) that no `Judged(event: ...)` of the file names, and each string
/// literal that begins a gate line by hand: an event's name from `printed`, then a colon.
pub fn breaches(
  file file: SourceFile,
  expected expected: List(String),
  printed printed: List(String),
) -> List(Breach) {
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
    })
    |> list.map(fn(literal) {
      Breach(
        path: file.path,
        line: syntax.line_of(text: file.text, byte_offset: literal.0),
        rule: "a gate line printed by hand, not through load_judged.judge",
      )
    })
  list.append(not_judged, by_hand)
}

/// The variant names the file's `Judged(event: ...)` calls give as the event.
fn judged_events(module: glance.Module) -> List(String) {
  syntax.calls(module)
  |> list.filter(fn(call) {
    case call.called {
      syntax.CalledByName(name: "Judged")
      | syntax.CalledThroughVariable(label: "Judged", ..) -> True
      syntax.CalledByName(..)
      | syntax.CalledThroughVariable(..)
      | syntax.CalledOtherwise -> False
    }
  })
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
        glance.LabelledField(..)
        | glance.UnlabelledField(..)
        | glance.ShorthandField(..) -> Error(Nil)
      }
    })
  })
}
