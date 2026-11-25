//// The judged-count rule. Expected values are the gates of the two load runs that decide
//// a merge: the fight run's strike rounds, strike answers and respawns, and the movement
//// run's moves read by a probe. Each must be judged through `genesis_prime/load_judged`
//// (a `Judged(event: ...)` naming it), and a line that begins with an event's name and a
//// colon must come from the shared function, not from the run's own text. The rule is
//// shown on planted files, then read over the two real ones.

import code_rule/judged_count
import code_rule/planted
import code_rule/repository
import code_rule/source.{type SourceFile}
import code_rule/syntax
import genesis_prime/load_judged
import gleam/list
import gleam/string
import owned_test
import unitest

const fight_path = "dev/genesis_prime/load_fight.gleam"

const moves_path = "dev/genesis_prime/load_moves.gleam"

/// Where each gate event is judged, by the variant's name: the fight run's three and the
/// movement run's one.
const gates = [
  #(fight_path, ["StrikeRounds", "StrikeAnswers", "Respawns"]),
  #(moves_path, ["MovesRead"]),
]

/// The printed name of each event, read from the shared function.
fn printed() -> List(String) {
  list.map(load_judged.all(), load_judged.name)
}

fn lines_of(
  file file: SourceFile,
  expected expected: List(String),
) -> List(Int) {
  judged_count.breaches(file:, expected:, printed: printed())
  |> planted.lines
}

pub fn every_gate_line_of_the_load_runs_calls_the_judged_count_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let judging = fn(events: List(String)) {
    list.flat_map(events, fn(event) {
      [
        "  let _ = load_judged.Judged(",
        "    event: load_judged." <> event <> ",",
        "    count: 1,",
        "    minimum: 1,",
        "  )",
      ]
    })
  }
  let planted_file = fn(body: List(String)) {
    planted.file(
      path: fight_path,
      lines: list.flatten([
        ["pub fn report() {"],
        body,
        ["}"],
      ]),
    )
  }
  assert lines_of(
      file: planted_file(judging(["StrikeRounds", "StrikeAnswers"])),
      expected: ["StrikeRounds", "StrikeAnswers"],
    )
    == []
    as "every expected event is judged"
  assert lines_of(file: planted_file(judging(["StrikeRounds"])), expected: [
      "StrikeRounds",
      "StrikeAnswers",
    ])
    == [1]
    as "an expected event that no Judged names is a breach, at the file's start"
  assert lines_of(
      file: planted_file(
        list.append(judging(["StrikeRounds"]), [
          "  io.println(\"strike rounds: \" <> int.to_string(rounds))",
        ]),
      ),
      expected: ["StrikeRounds"],
    )
    == [7]
    as "a gate line printed by hand is a breach, at its line"
  assert lines_of(
      file: planted_file([
        "  io.println(\"strike rounds closed: \" <> int.to_string(rounds))",
      ]),
      expected: [],
    )
    == []
    as "a line that only starts with the event's words is not a gate line"
  // The events the rule expects are the events the shared module has.
  let variants =
    syntax.parse(source.SourceFile(
      path: "src/load_judged.gleam",
      text: source.read("dev/genesis_prime/load_judged.gleam"),
    )).custom_types
    |> list.filter(fn(definition) { definition.definition.name == "Event" })
    |> list.flat_map(fn(definition) {
      list.map(definition.definition.variants, fn(variant) { variant.name })
    })
  assert list.sort(variants, by: string.compare)
    == list.sort(list.flat_map(gates, fn(gate) { gate.1 }), by: string.compare)
    as "every event of the shared module is a gate of one of the runs"
  list.each(gates, fn(gate) {
    let assert [file] =
      repository.sources(["dev"])
      |> list.filter(fn(file) { file.path == gate.0 })
    assert lines_of(file:, expected: gate.1) == [] as gate.0
  })
}
