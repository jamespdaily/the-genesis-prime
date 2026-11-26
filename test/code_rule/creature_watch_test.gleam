//// A creature watches its map's run and nothing else: a creature hears of the end of a
//// player's connection from the map (`CasterGone`), so it holds no watch of a connection.
//// Expected value is the rule: the one `Watch` effect of the creature's modules is the run's.

import code_rule/planted
import code_rule/source.{type SourceFile}
import code_rule/syntax
import gleam/list
import owned_test
import unitest

const creature_directory = "src/genesis_prime/world_map"

/// The `Watch` effects the file builds, one entry for each, as the file's path.
fn watches(file file: SourceFile) -> List(String) {
  syntax.calls(syntax.parse(file))
  |> list.filter(syntax.is_step_effect(_, name: "Watch"))
  |> list.map(fn(_) { file.path })
}

pub fn a_creature_watches_only_its_map_run_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let planted_file =
    planted.file(path: creature_directory <> "/creature.gleam", lines: [
      "fn the_run() {",
      "  OwnEffect(Watch(watch: run_watch, target: Map(a, b)))",
      "}",
      "",
      "fn a_connection(by) {",
      "  step.Watch(watch: w, target: Connection(by))",
      "}",
      "",
      "fn an_unwatch(w) {",
      "  step.Unwatch(watch: w)",
      "}",
    ])
  assert watches(file: planted_file) == [planted_file.path, planted_file.path]
    as "a watch, qualified or not, is found; an Unwatch is none"
  assert list.flat_map(syntax.creature_modules(), fn(file) { watches(file:) })
    == [creature_directory <> "/creature.gleam"]
    as "the creature's modules build one Watch, the run's"
}
