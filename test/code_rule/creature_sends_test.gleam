//// The creature sends only to its map. Expected value is the rule: a creature's
//// news, answers, credits and fight tells reach a player through the creature's map
//// (genesis_prime/world_map/map `Snapshot`, `Broadcast` and `Relay`), so a player has one
//// sender for what concerns a creature. A `Send` in the creature's modules whose `to:`
//// names anything but a `Map(...)` address, a connection or a strike's `from` among them,
//// is a breach, reported at its line. The rule is shown on a planted file, then read over
//// the real ones.

import code_rule/planted
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import unitest

const world_map_directory = "src/genesis_prime/world_map"

/// The lines of the file's `Send`s whose `to:` is not a `Map(...)` address.
fn sends_elsewhere(file file: SourceFile) -> List(Int) {
  syntax.calls(syntax.parse(file))
  |> list.filter_map(fn(call) {
    let is_send = case call.called {
      syntax.CalledByName(name: "Send") -> True
      syntax.CalledThroughVariable(variable: "step", label: "Send") -> True
      syntax.CalledByName(..)
      | syntax.CalledThroughVariable(..)
      | syntax.CalledOtherwise -> False
    }
    let line = syntax.line_of(text: file.text, byte_offset: call.function.start)
    case is_send {
      False -> Error(Nil)
      True ->
        case
          syntax.argument(
            arguments: call.arguments,
            label: "to",
            position: syntax.FirstArgument,
          )
        {
          Some(address) ->
            case syntax.calls_variant(address, qualifier: "step", name: "Map") {
              True -> Error(Nil)
              False -> Ok(line)
            }
          None -> Ok(line)
        }
    }
  })
  |> list.sort(int.compare)
}

/// The creature's modules: every file of the world map's folder whose name starts with
/// `creature`.
fn creature_modules() -> List(SourceFile) {
  source.files(under: world_map_directory)
  |> list.filter(fn(file) {
    string.starts_with(file.path, world_map_directory <> "/creature")
  })
}

pub fn a_creature_sends_only_to_its_map_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: world_map_directory <> "/creature.gleam", lines: [
      "fn to_the_map() {",
      "  OwnEffect(Send(to: Map(map: a, incarnation: b), message: m))",
      "}",
      "",
      "fn qualified() {",
      "  Send(to: step.Map(map: a, incarnation: b), message: m)",
      "}",
      "",
      "fn to_a_connection() {",
      "  OwnEffect(Send(to: Connection(viewer.0), message: m))",
      "}",
      "",
      "fn to_the_address_the_strike_came_from() {",
      "  OwnEffect(Send(to: tell.from, message: m))",
      "}",
    ])
  assert sends_elsewhere(file: planted_file) == [10, 14]
    as "a send to a connection or to the address a strike came from is found, and a send to a map is not"
  assert list.flat_map(creature_modules(), fn(file) {
      list.map(sends_elsewhere(file:), fn(line) {
        file.path <> ":" <> int.to_string(line)
      })
    })
    == []
    as "each send of a creature's modules names its map"
}
