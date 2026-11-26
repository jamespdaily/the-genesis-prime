//// A creature hears about a player only from its map. Expected value is the rule: a
//// player's strike, move, answer or cast effect reaches a creature as the map's
//// `ToldCreature` (genesis_prime/world_map/map `TellCreature`), so a creature has one
//// sender for what concerns a player. Two rules, each shown on a planted file, then read
//// over the real ones.
//// - A connection rule's `Tell` whose `to:` names a creature, or whose request is a
////   `TellCreature` and whose `to:` is not a map, is a breach, reported at its line.
//// - The creature registry is told only by the map's reach: a call of
////   `creature_registry.tell` in `src` or `dev` outside the function `map_reach` of
////   `genesis_prime/server` is a breach, reported as the file and the function. The load
////   tools' walkers tell creatures as players' connections do, through the map, so a run
////   measures the path the server takes.

import code_rule/planted
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import unitest

const game_directory = "src/genesis_prime/game"

const registry_module = "genesis_prime/world_map/creature_registry"

/// The lines of the file's `Tell` effects that tell a creature: `to:` names a `Creature(...)`
/// address, or the request is a `TellCreature(...)` and `to:` is no `Map(...)` address.
fn tells_a_creature(file file: SourceFile) -> List(Int) {
  syntax.calls(syntax.parse(file))
  |> list.filter_map(fn(call) {
    let is_tell = syntax.is_step_effect(call, name: "Tell")
    let to =
      syntax.argument(
        arguments: call.arguments,
        label: "to",
        position: syntax.FirstArgument,
      )
    let to_a_creature = case to {
      Some(address) ->
        syntax.calls_variant(address, qualifier: "step", name: "Creature")
      None -> False
    }
    let to_a_map = case to {
      Some(address) ->
        syntax.calls_variant(address, qualifier: "step", name: "Map")
      None -> False
    }
    let tells_the_creature = case
      syntax.argument(
        arguments: call.arguments,
        label: "request",
        position: syntax.LastArgument,
      )
    {
      Some(request) ->
        syntax.calls_variant(
          request,
          qualifier: "client_connection",
          name: "TellCreature",
        )
      None -> False
    }
    case is_tell && { to_a_creature || { tells_the_creature && !to_a_map } } {
      True ->
        Ok(syntax.line_of(text: file.text, byte_offset: call.function.start))
      False -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}

/// The functions of the file, as `function` names, that call `creature_registry.tell`,
/// however the module is imported.
fn registry_tellers(file file: SourceFile) -> List(String) {
  let module = syntax.parse(file)
  let starts =
    list.map(module.functions, fn(definition) {
      #(definition.definition.location.start, definition.definition.name)
    })
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  syntax.references_to(module:, from: [registry_module], named: ["tell"])
  |> list.map(fn(reference) {
    let at = syntax.location_of(reference).start
    let assert Ok(#(_, name)) =
      starts
      |> list.filter(fn(function) { function.0 <= at })
      |> list.last
      as "a reference lies in a function"
    file.path <> ":" <> name
  })
  |> list.unique
}

pub fn a_connection_tells_a_creature_nothing_but_through_its_map_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: game_directory <> "/connection/casting.gleam", lines: [
      "fn to_the_map() {",
      "  OwnEffect(step.Tell(to: step.Map(map: a, incarnation: b), request: r))",
      "}",
      "",
      "fn to_a_connection() {",
      "  OwnEffect(step.Tell(to: step.Connection(c), request: r))",
      "}",
      "",
      "fn to_a_creature() {",
      "  OwnEffect(step.Tell(to: step.Creature(map: a, incarnation: b, unit_id: u, life: l), request: r))",
      "}",
      "",
      "fn to_a_creature_unqualified() {",
      "  OwnEffect(Tell(to: Creature(map: a, incarnation: b, unit_id: u, life: l), request: r))",
      "}",
      "",
      "fn a_creature_request_to_an_address_held_in_a_variable(to) {",
      "  OwnEffect(step.Tell(to:, request: client_connection.TellCreature(a, b, c, d, e)))",
      "}",
      "",
      "fn a_creature_request_to_the_map() {",
      "  OwnEffect(step.Tell(to: step.Map(map: a, incarnation: b), request: client_connection.TellCreature(a, b, c, d, e)))",
      "}",
    ])
  assert tells_a_creature(file: planted_file) == [10, 14, 18]
    as "a tell to a creature, qualified or not, and a creature request to an address held in a variable are found; a tell to a map or a connection, and a creature request to the map, are not"
  assert list.flat_map(source.files(under: game_directory), fn(file) {
      list.map(tells_a_creature(file:), fn(line) {
        file.path <> ":" <> int.to_string(line)
      })
    })
    == []
    as "no connection rule tells a creature, but through its map"
}

pub fn the_creature_registry_is_told_only_by_the_maps_reach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: "src/genesis_prime/server.gleam", lines: [
      "import genesis_prime/world_map/creature_registry",
      "",
      "fn map_reach() {",
      "  creature_registry.tell(a)",
      "}",
      "",
      "fn finds() {",
      "  creature_registry.find(a)",
      "}",
    ])
  let aliased_file =
    planted.file(path: "src/genesis_prime/other.gleam", lines: [
      "import genesis_prime/world_map/creature_registry as registry",
      "",
      "fn tell_creature() {",
      "  registry.tell(a)",
      "}",
    ])
  let a_tool_file =
    planted.file(path: "dev/genesis_prime/load_tool.gleam", lines: [
      "import genesis_prime/world_map/creature_registry",
      "",
      "fn walks() {",
      "  creature_registry.tell(a)",
      "}",
    ])
  assert registry_tellers(file: planted_file)
    == ["src/genesis_prime/server.gleam:map_reach"]
    as "the function that tells the registry is found, and a lookup is not a tell"
  assert registry_tellers(file: aliased_file)
    == ["src/genesis_prime/other.gleam:tell_creature"]
    as "a tell through the module's alias is found"
  assert registry_tellers(file: a_tool_file)
    == ["dev/genesis_prime/load_tool.gleam:walks"]
    as "a tell from a load tool is found"
  assert list.flat_map(
      list.append(source.files(under: "src"), source.files(under: "dev")),
      fn(file) { registry_tellers(file:) },
    )
    == ["src/genesis_prime/server.gleam:map_reach"]
    as "the creature registry is told by the map's reach alone, by the server and by the load tools"
}
