//// The map draws no random value. Expected value is Design run A, section 1.1: the
//// relay carries values and draws none, and no process of the world map has a random
//// stream. The rule is shown on a planted file, then read over every file of
//// `world_map/`.

import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/int
import gleam/list
import owned_test
import unitest

/// The functions a file must not call: `module.name` as written.
const drawing_calls = ["int.random", "float.random", "list.shuffle"]

/// What the file draws: an import of `genesis_prime/random` and a call or reference of
/// `int.random`, `float.random` or `list.shuffle`, each with its line.
fn draws(file file: SourceFile) -> List(String) {
  let module = syntax.parse(file)
  let imports =
    list.filter_map(module.imports, fn(definition) {
      case definition.definition.module == "genesis_prime/random" {
        True ->
          Ok(#(
            definition.definition.location.start,
            "imports genesis_prime/random",
          ))
        False -> Error(Nil)
      }
    })
  let calls =
    list.filter_map(syntax.references(module), fn(reference) {
      case reference {
        syntax.Qualified(location:, qualifier:, name:) -> {
          let written = qualifier <> "." <> name
          case list.contains(drawing_calls, written) {
            True -> Ok(#(location.start, "calls " <> written))
            False -> Error(Nil)
          }
        }
        syntax.Unqualified(..) -> Error(Nil)
      }
    })
  list.append(imports, calls)
  |> list.sort(by: fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) {
    int.to_string(syntax.line_of(text: file.text, byte_offset: entry.0))
    <> ": "
    <> entry.1
  })
}

pub fn nothing_in_the_world_map_draws_a_random_value_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: "src/genesis_prime/world_map/planted.gleam", lines: [
      "import genesis_prime/random",
      "import gleam/float",
      "import gleam/int",
      "import gleam/list",
      "",
      "pub fn roll() {",
      "  let a = int.random(6)",
      "  let b = float.random()",
      "  let c = list.shuffle([1, 2])",
      "  let d = int.to_string(a)",
      "  #(a, b, c, d)",
      "}",
    ])
  let renamed_file =
    planted.file(path: "src/genesis_prime/world_map/renamed.gleam", lines: [
      "import gleam/float as coin",
      "import gleam/int as dice",
      "import gleam/list.{shuffle as mix}",
      "import gleam/int.{random}",
      "",
      "pub fn roll() {",
      "  let a = dice.random(6)",
      "  let b = coin.random()",
      "  let c = mix([1, 2])",
      "  let d = random(6)",
      "  #(a, b, c, d)",
      "}",
    ])
  assert draws(file: planted_file)
    == [
      "1: imports genesis_prime/random",
      "7: calls int.random",
      "8: calls float.random",
      "9: calls list.shuffle",
    ]
    as "the import and each of the three random calls are found, and a call of another function is not"
  assert draws(file: renamed_file)
    == [
      "7: calls int.random",
      "8: calls float.random",
      "9: calls list.shuffle",
      "10: calls int.random",
    ]
    as "a call through an aliased import of the module, through an aliased unqualified import and through an unqualified import is found under the module's own name"
  assert repository.sources(under: ["src/genesis_prime/world_map"])
    |> list.flat_map(fn(file) { draws(file:) })
    == []
    as "no file of the world map imports the random module or draws a value"
}
