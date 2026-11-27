//// The map draws no random value. Expected value is Design run A, section 1.1: the
//// relay carries values and draws none, and no process of the world map has a random
//// stream. The rule is shown on a planted file, then read over every file of
//// `world_map/`.

import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import gleam/list
import owned_test
import unitest

/// What the file draws: an import of `genesis_prime/random` and a call of
/// `int.random`, `float.random` or `list.shuffle`, each with its line.
fn draws(file file: SourceFile) -> List(String) {
  let _ = file
  []
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
  assert draws(file: planted_file)
    == [
      "1: imports genesis_prime/random",
      "7: calls int.random",
      "8: calls float.random",
      "9: calls list.shuffle",
    ]
    as "the import and each of the three random calls are found, and a call of another function is not"
  assert repository.sources(under: ["src/genesis_prime/world_map"])
    |> list.flat_map(fn(file) { draws(file:) })
    == []
    as "no file of the world map imports the random module or draws a value"
}
