//// The judged-count rule. Expected values are the gates of the two load runs that decide
//// a merge: the fight run's strike rounds, strike answers and respawns, and the movement
//// run's moves read by a probe. Each must be judged through `genesis_prime/load_judged`
//// (a `Judged(event: ...)` naming it, inside the `judged:` of a `load_judged.judge` whose
//// verdict is given to `load_judged.require`), and no string of the tools may print a
//// verdict: a word `pass`, `fail` or `gate` in any form, or an event's name and a colon. The
//// rule is shown on planted files, then read over the two real ones.

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

/// A planted run: the events it judges inside a `load_judged.judge`, the line that gives
/// the verdict to `require`, then the extra lines. With one event, the lines are numbered:
/// 1 the function, 2 to 8 the judge call, 5 the event, 9 the require, 10 the first extra.
fn run(
  events events: List(String),
  require require: String,
  extra extra: List(String),
) -> SourceFile {
  planted.file(
    path: fight_path,
    lines: list.flatten([
      [
        "pub fn report() {",
        "  let judged =",
        "    load_judged.judge(",
        "      judged: [",
      ],
      list.map(events, fn(event) {
        "        load_judged.Judged(event: load_judged."
        <> event
        <> ", count: 1, minimum: 1),"
      }),
      ["      ],", "      conditions: [],", "    )", require],
      extra,
      ["}"],
    ]),
  )
}

const required = "  load_judged.require(verdict: judged)"

pub fn every_gate_line_of_the_load_runs_calls_the_judged_count_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let rows = [
    #(
      "every expected event is judged and its verdict required",
      run(
        events: ["StrikeRounds", "StrikeAnswers"],
        require: required,
        extra: [],
      ),
      ["StrikeRounds", "StrikeAnswers"],
      [],
    ),
    #(
      "an expected event that no Judged names is a breach, at the file's start",
      run(events: ["StrikeRounds"], require: required, extra: []),
      ["StrikeRounds", "StrikeAnswers"],
      [1],
    ),
    #(
      "a gate line printed by hand is a breach, at its line",
      run(events: ["StrikeRounds"], require: required, extra: [
        "  io.println(\"strike rounds: \" <> int.to_string(rounds))",
      ]),
      ["StrikeRounds"],
      [10],
    ),
    #(
      "a line that only starts with the event's words is not a gate line",
      run(events: ["StrikeRounds"], require: required, extra: [
        "  io.println(\"strike rounds closed: \" <> int.to_string(rounds))",
      ]),
      ["StrikeRounds"],
      [],
    ),
    #(
      "a gate verdict printed by hand, as a run once printed its respawn gate",
      run(events: ["Respawns"], require: required, extra: [
        "  io.println(\"respawn gate: passes\")",
      ]),
      ["Respawns"],
      [10],
    ),
    #(
      "a failure line printed by hand",
      run(events: ["Respawns"], require: required, extra: [
        "  io.println(\"fail: the map falls behind\")",
      ]),
      ["Respawns"],
      [10],
    ),
    #(
      "a pass line printed by hand",
      run(events: ["Respawns"], require: required, extra: [
        "  io.println(\"pass: the map keeps up\")",
      ]),
      ["Respawns"],
      [10],
    ),
    #(
      "a word that only contains a verdict word is no verdict",
      run(events: ["Respawns"], require: required, extra: [
        "  io.println(\"navigate the passage\")",
      ]),
      ["Respawns"],
      [],
    ),
    #(
      "a verdict that is never given to require is a breach, at the first count",
      run(events: ["Respawns"], require: "  let _ = judged", extra: []),
      ["Respawns"],
      [5],
    ),
    #(
      "a require of another value than the judged verdict is a breach",
      run(
        events: ["Respawns"],
        require: "  load_judged.require(verdict: other)",
        extra: [],
      ),
      ["Respawns"],
      [5],
    ),
    #(
      "a count outside the judged of a judge call is a breach, at the count",
      planted.file(path: fight_path, lines: [
        "pub fn report() {",
        "  let _ = load_judged.Judged(event: load_judged.Respawns, count: 1, minimum: 1)",
        "  let judged = load_judged.judge(judged: [], conditions: [])",
        required,
        "}",
      ]),
      ["Respawns"],
      [2],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, file, expected, lines) = row
    assert lines_of(file:, expected:) == lines as reason
  })
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
  assert list.length(load_judged.all()) == list.length(variants)
    as "the shared module's list of events holds each variant, so each has its printed name checked"
  list.each(gates, fn(gate) {
    let assert [file] =
      repository.sources(["dev"])
      |> list.filter(fn(file) { file.path == gate.0 })
    assert lines_of(file:, expected: gate.1) == [] as gate.0
  })
}
