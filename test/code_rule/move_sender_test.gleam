//// The move rule. Expected value is the rule: a player's move goes from its mover to each
//// viewer in its own copy, stamped with the generation of that relation
//// (genesis_prime/game/move_stamp), and through no map, so the map and the relay can hold
//// no move. A reference to `TellMove` in a file of `src` or `dev` other than the mover's
//// (`genesis_prime/game/connection/movement`), an import of `move_stamp` or
//// `relayed_movement` in a file of the world map, and an import of either in the news
//// type (`genesis_prime/game/unit_news`) are breaches. The rule is shown on planted
//// files, then read over the real ones.

import code_rule/planted
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

const request_module = "genesis_prime/client_connection"

const mover = "src/genesis_prime/game/connection/movement.gleam"

const unit_news = "src/genesis_prime/game/unit_news.gleam"

const world_map_directory = "src/genesis_prime/world_map"

const move_modules = [
  "genesis_prime/game/move_stamp", "genesis_prime/message/relayed_movement",
]

/// The lines of the file that build the request that tells a viewer a move.
fn tells_a_move(file file: SourceFile) -> List(Int) {
  syntax.references_to(
    module: syntax.parse(file),
    from: [request_module],
    named: ["TellMove"],
  )
  |> list.map(fn(reference) {
    syntax.line_of(
      text: file.text,
      byte_offset: syntax.location_of(reference).start,
    )
  })
  |> list.sort(int.compare)
}

/// The move modules the file imports.
fn imports_a_move(file file: SourceFile) -> List(String) {
  syntax.imported_modules(file)
  |> list.filter(list.contains(move_modules, _))
  |> list.sort(string.compare)
}

pub fn the_map_and_the_relay_hold_no_move_and_a_move_is_told_only_by_the_mover_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: "src/genesis_prime/world_map/map.gleam", lines: [
      "import genesis_prime/client_connection",
      "import genesis_prime/client_connection as requests",
      "import genesis_prime/client_connection.{TellMove as Moves}",
      "",
      "fn qualified() {",
      "  client_connection.TellMove(stay: a, move: b)",
      "}",
      "",
      "fn aliased() {",
      "  requests.TellMove(stay: a, move: b)",
      "}",
      "",
      "fn unqualified() {",
      "  Moves(stay: a, move: b)",
      "}",
      "",
      "fn another_request() {",
      "  client_connection.TellPeer(stay: a, news: b)",
      "}",
    ])
  assert tells_a_move(file: planted_file) == [6, 10, 14]
    as "a build through the module, through its alias and through an unqualified import is found, and another request is not"
  let imports =
    planted.file(path: "src/genesis_prime/world_map/relay.gleam", lines: [
      "import genesis_prime/game/move_stamp",
      "import genesis_prime/message/relayed_movement.{type RelayedMovement}",
      "import genesis_prime/game/movement",
    ])
  assert imports_a_move(file: imports)
    == [
      "genesis_prime/game/move_stamp",
      "genesis_prime/message/relayed_movement",
    ]
    as "an import of a move module is found, and another module is not"
  let builders =
    list.append(source.files(under: "src"), source.files(under: "dev"))
    |> list.filter(fn(file) { tells_a_move(file:) != [] })
    |> list.map(fn(file) { file.path })
  assert builders == [mover]
    as "the mover is the one file that builds a move's request"
  assert list.flat_map(source.files(under: world_map_directory), fn(file) {
      list.map(imports_a_move(file:), fn(module) { file.path <> " " <> module })
    })
    == []
    as "no file of the world map imports a move"
  assert list.flat_map(source.files(under: "src/genesis_prime/game"), fn(file) {
      case file.path == unit_news {
        True -> imports_a_move(file:)
        False -> []
      }
    })
    == []
    as "the news type holds no move"
}
