//// The move rule. Expected value is the rule: a player's move goes from its mover to each
//// viewer in its own copy, stamped with the generation of that relation
//// (genesis_prime/game/move_stamp), and through no map, so the map and the relay can hold
//// no move. A reference to `TellMove` in a file of `src` or `dev` other than the mover's
//// (`genesis_prime/game/connection/movement`), an import of `move_stamp` or
//// `relayed_movement` in a file of the world map, and an import of either, or a field of a move's type, in the news
//// type (`genesis_prime/shared/unit_news`) are breaches. The rule is shown on planted
//// files, then read over the real ones.

import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import code_rule/syntax
import glance
import gleam/int
import gleam/list
import gleam/string
import owned_test
import unitest

const request_module = "genesis_prime/client_connection"

const mover = "src/genesis_prime/game/connection/movement.gleam"

const unit_news = "src/genesis_prime/shared/unit_news.gleam"

const world_map_directory = "src/genesis_prime/world_map"

const shared_directory = "src/genesis_prime/shared"

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

/// The types a move is made of, by the names the client's reader and the relay give them.
const move_types = ["Move", "RelayedMovement", "UnitPositionCommand"]

/// The variants of the file's custom type `News` that hold, at any depth, a type a move is
/// made of.
fn news_fields_of_a_move(file file: SourceFile) -> List(String) {
  list.flat_map(syntax.parse(file).custom_types, fn(definition) {
    case definition.definition.name {
      "News" ->
        list.filter(definition.definition.variants, holds_a_move)
        |> list.map(fn(variant) { variant.name })
      _ -> []
    }
  })
}

fn holds_a_move(variant variant: glance.Variant) -> Bool {
  list.any(variant.fields, fn(field) {
    list.any(type_names(of: field.item), list.contains(move_types, _))
  })
}

/// The name of each named type in `type_`, at any depth.
fn type_names(of type_: glance.Type) -> List(String) {
  case type_ {
    glance.NamedType(name:, parameters:, ..) -> [
      name,
      ..list.flat_map(parameters, type_names)
    ]
    glance.TupleType(elements:, ..) -> list.flat_map(elements, type_names)
    glance.FunctionType(parameters:, return:, ..) ->
      list.flat_map([return, ..parameters], type_names)
    glance.VariableType(..) | glance.HoleType(..) -> []
  }
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
      "  client_connection.TellBroadcast(connection: a, stay: b, news: c)",
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
  assert list.flat_map(
      repository.sources(under: [world_map_directory, shared_directory]),
      fn(file) {
        list.map(imports_a_move(file:), fn(module) {
          file.path <> " " <> module
        })
      },
    )
    == []
    as "no file of the world map or the shared folder imports a move"
  let planted_news =
    planted.file(path: unit_news, lines: [
      "pub type News {",
      "  Health(points: Int)",
      "  Moving(commands: List(RelayedMovement))",
      "  Walked(at: option.Option(unit_position_command.UnitPositionCommand))",
      "}",
    ])
  assert news_fields_of_a_move(file: planted_news) == ["Moving", "Walked"]
    as "a variant whose field holds a move's type, at any depth, is found, and another is not"
  let news_files =
    list.filter(source.files(under: "src/genesis_prime/game"), fn(file) {
      file.path == unit_news
    })
  assert list.length(news_files) == 1 as "the news type's file is found"
  assert list.flat_map(news_files, fn(file) {
      list.append(imports_a_move(file:), news_fields_of_a_move(file:))
    })
    == []
    as "the news type holds no move"
}
