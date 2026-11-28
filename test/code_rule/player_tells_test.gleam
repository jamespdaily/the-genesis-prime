//// The player tells rule. Expected value is the rule: a player's connection tells another
//// player's connection nothing itself (genesis_prime/world_map/map `PlayerBroadcast`,
//// `PlayerSnapshot`, `TellLanding` and `Say`), so a viewer has one sender for what concerns
//// another player: the map. The types hold most of it: the request has no variant for news,
//// a landing or a local line to a connection, and a `TellChat` cannot carry a `Said` line
//// (genesis_prime/shared/chat_tell). What the types cannot hold is the address: a `Tell` effect
//// in `src/genesis_prime/game` whose `to:` is a `step.Connection(...)` or `step.Unit(...)` address is a breach,
//// reported at its line, unless it tells `TellMove`, a mover's chunk of its own move to a
//// viewer in its own copy, which only `sends_the_move_to_the_viewers` of the mover
//// (`genesis_prime/game/connection/movement`) may build, or `TellChat`, which goes between
//// characters and not between players in sight (a whisper's reply, `Heard` and `NotHeard`).
//// The rule is shown on planted files, then read over the real ones.

import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import code_rule/syntax
import glance
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import unitest

const game_directory = "src/genesis_prime/game"

const shared_directory = "src/genesis_prime/shared"

const mover = "src/genesis_prime/game/connection/movement.gleam"

const mover_function = "sends_the_move_to_the_viewers"

/// The name of the variant an expression calls, written `Name(...)` or `qualifier.Name(...)`,
/// or `""` for any other expression.
fn called_variant(expression expression: glance.Expression) -> String {
  case expression {
    glance.Call(function: glance.Variable(name:, ..), ..) -> name
    glance.Call(function: glance.FieldAccess(label:, ..), ..) -> label
    _ -> ""
  }
}

/// What a `Tell` to a connection tells, by the variant of its request.
type Told {
  Told(line: Int, request: String)
}

/// What the request of a `Tell` is, by its variant, and `""` when the request is no call.
fn request_told(request request: Option(glance.Expression)) -> String {
  case request {
    Some(expression) -> called_variant(expression:)
    None -> ""
  }
}

/// Whether the call gives a `request:` of its own: the connection rule's `Tell` effect does,
/// the chat feature's effect of the same name gives a `tell:`.
fn gives_a_request(call call: syntax.Call) -> Bool {
  list.any(call.arguments, fn(argument) {
    case argument {
      glance.LabelledField(label: "request", ..)
      | glance.ShorthandField(label: "request", ..) -> True
      glance.LabelledField(..)
      | glance.ShorthandField(..)
      | glance.UnlabelledField(..) -> False
    }
  })
}

/// Whether the call is a `Tell` effect with a request to a `step.Connection(...)` or a
/// `step.Unit(...)` address.
fn tells_a_connection(call call: syntax.Call) -> Bool {
  use <- bool.guard(
    when: !syntax.is_step_effect(call, name: "Tell") || !gives_a_request(call:),
    return: False,
  )
  case
    syntax.argument(
      arguments: call.arguments,
      label: "to",
      position: syntax.FirstArgument,
    )
  {
    Some(address) ->
      syntax.calls_variant(address, qualifier: "step", name: "Connection")
      || syntax.calls_variant(address, qualifier: "step", name: "Unit")
    None -> False
  }
}

/// The `Tell` effects of the file whose `to:` is a `step.Connection(...)` or `step.Unit(...)`
/// address, each with its line and what it tells.
fn tells_to_a_connection(file file: SourceFile) -> List(Told) {
  syntax.calls(syntax.parse(file))
  |> list.filter(tells_a_connection)
  |> list.map(fn(call) {
    Told(
      line: syntax.line_of(text: file.text, byte_offset: call.function.start),
      request: request_told(request: syntax.argument(
        arguments: call.arguments,
        label: "request",
        position: syntax.LastArgument,
      )),
    )
  })
}

/// The lines of the file where a player tells another player's connection something a
/// viewer must have from the map: every tell to a connection but a move and a chat tell
/// between characters.
fn breaches(file file: SourceFile) -> List(Int) {
  tells_to_a_connection(file:)
  |> list.filter(fn(told) {
    told.request != "TellMove" && told.request != "TellChat"
  })
  |> list.map(fn(told) { told.line })
  |> list.sort(int.compare)
}

/// The lines of the file that build `TellMove` to a connection.
fn moves(file file: SourceFile) -> List(Int) {
  tells_to_a_connection(file:)
  |> list.filter(fn(told) { told.request == "TellMove" })
  |> list.map(fn(told) { told.line })
}

/// Whether the line lies inside the function `name` of the file.
fn inside(file file: SourceFile, line line: Int, name name: String) -> Bool {
  list.any(syntax.parse(file).functions, fn(definition) {
    let function = definition.definition
    function.name == name
    && syntax.line_of(text: file.text, byte_offset: function.location.start)
    <= line
    && line
    <= syntax.line_of(text: file.text, byte_offset: function.location.end)
  })
}

pub fn a_player_tells_another_player_only_through_its_map_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: game_directory <> "/connection/state.gleam", lines: [
      "fn news() {",
      "  OwnEffect(step.Tell(to: step.Connection(viewer.0), request: TellBroadcast(unit: a, news: c)))",
      "}",
      "",
      "fn a_heal() {",
      "  OwnEffect(step.Tell(",
      "    to: step.Connection(connection: strike.from),",
      "    request: TellLanding(unit: a, to: c, landing: e),",
      "  ))",
      "}",
      "",
      "fn a_line() {",
      "  OwnEffect(step.Tell(to: step.Connection(to), request: TellSay(unit: a, said: c)))",
      "}",
      "",
      "fn a_whisper() {",
      "  OwnEffect(step.Tell(to: step.Connection(from), request: TellChat(tell: Heard(whisper: 1, name: n))))",
      "}",
      "",
      "fn to_the_map() {",
      "  OwnEffect(step.Tell(to: step.Map(map: a, incarnation: b), request: TellBroadcast(connection: c, stay: s, news: n)))",
      "}",
      "",
      "fn a_move() {",
      "  OwnEffect(step.Tell(to: step.Unit(v), request: client_connection.TellMove(move: m)))",
      "}",
    ])
  assert breaches(file: planted_file) == [2, 6, 13]
    as "a tell to a connection of news, a landing or a line is found, and a whisper's reply, a tell to the map and a move are not"
  assert moves(file: planted_file) == [25]
    as "a move told to a connection is found, and no other tell is"
  let files = repository.sources(under: [game_directory, shared_directory])
  assert list.flat_map(files, fn(file) {
      list.map(breaches(file:), fn(line) {
        file.path <> ":" <> int.to_string(line)
      })
    })
    == []
    as "no file of the game tells a player's connection anything but a move or a chat tell between characters: the map tells it"
  let movers =
    list.flat_map(files, fn(file) {
      list.map(moves(file:), fn(line) { #(file, line) })
    })
  assert list.map(movers, fn(mover_line) { { mover_line.0 }.path }) == [mover]
    as "a move is told to a connection by the mover's file alone"
  assert list.all(movers, fn(mover_line) {
    inside(file: mover_line.0, line: mover_line.1, name: mover_function)
  })
    as "and by its one function, which builds each viewer's chunk from the copy"
}
