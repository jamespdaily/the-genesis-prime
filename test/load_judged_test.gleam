//// What the load runs' judged counts say, from planted counts: a gate that decides a
//// merge must fail a run that saw none of the events it judges (one run passed with no
//// strike round measured, another with no respawn seen), one that judged nothing, and one
//// whose other condition (the map keeping up, the step's verdict) did not hold. The wording
//// is the shared function's (`genesis_prime/load_judged`): the event's name, its count, its
//// minimum.

import genesis_prime/load_judged.{
  type Verdict, Condition, Fails, Judged, MovesRead, Passes, Respawns,
  StrikeAnswers, StrikeRounds,
}
import gleam/list
import gleam/string
import owned_test

/// The lines of the verdict, tagged by how it came out.
fn told(verdict verdict: Verdict) -> #(Bool, List(String)) {
  case verdict {
    Passes(lines:, ..) -> #(True, lines)
    Fails(lines:, ..) -> #(False, lines)
  }
}

pub fn a_judged_count_below_its_minimum_fails_the_run_and_names_the_event_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "no event seen, of a minimum of 1",
      Judged(event: StrikeRounds, count: 0, minimum: 1),
      "strike rounds: 0, below its minimum of 1",
    ),
    #(
      "3 seen, of a minimum of 5",
      Judged(event: StrikeAnswers, count: 3, minimum: 5),
      "strike answers: 3, below its minimum of 5",
    ),
  ]
  list.each(rows, fn(row) {
    let #(what, judged, line) = row
    assert told(verdict: load_judged.judge(judged: [judged], conditions: []))
      == #(False, [line])
      as what
  })
}

pub fn a_judged_count_at_or_above_its_minimum_passes_and_prints_its_count_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "a count equal to the minimum",
      Judged(event: Respawns, count: 2, minimum: 2),
      "respawns: 2 (minimum 2)",
    ),
    #(
      "a count above it",
      Judged(event: MovesRead, count: 900, minimum: 1),
      "moves read by a probe: 900 (minimum 1)",
    ),
  ]
  list.each(rows, fn(row) {
    let #(what, judged, line) = row
    assert told(verdict: load_judged.judge(judged: [judged], conditions: []))
      == #(True, [line])
      as what
  })
}

pub fn a_run_with_any_judged_count_below_its_minimum_fails_as_a_whole_test() -> Nil {
  use <- owned_test.run(5000)
  let seen = Judged(event: StrikeRounds, count: 4, minimum: 1)
  let none = Judged(event: StrikeAnswers, count: 0, minimum: 1)
  let enough = Judged(event: Respawns, count: 2, minimum: 2)
  case load_judged.judge(judged: [seen, none, enough], conditions: []) {
    Fails(lines:, summary:) -> {
      assert list.length(lines) == 3 as "every event has its line"
      assert string.contains(summary, "strike answers")
        as "the summary names the event below its minimum"
      assert !string.contains(summary, "strike rounds")
        && !string.contains(summary, "respawns")
        as "and no other"
    }
    Passes(..) -> panic as "a run with an event below its minimum passed"
  }
  assert told(
    verdict: load_judged.judge(judged: [seen, enough], conditions: []),
  ).0
    as "with every event at or above its minimum the run passes"
}

pub fn a_run_that_judged_nothing_or_holds_not_a_condition_fails_as_a_whole_test() -> Nil {
  use <- owned_test.run(5000)
  let seen = Judged(event: StrikeRounds, count: 4, minimum: 1)
  let map_behind =
    Condition(held: False, said: "the map falls behind: its queue grew")
  let map_keeps_up = Condition(held: True, said: "the map keeps up")
  let rows = [
    #("no event judged", [], [], False, "nothing was judged"),
    #(
      "no event judged, a condition held",
      [],
      [map_keeps_up],
      False,
      "nothing was judged",
    ),
    #(
      "every count enough, a condition not held",
      [seen],
      [map_keeps_up, map_behind],
      False,
      "the map falls behind: its queue grew",
    ),
    #(
      "every count enough, every condition held",
      [seen],
      [map_keeps_up],
      True,
      "pass: the map keeps up; every judged count is at or above its minimum",
    ),
  ]
  list.each(rows, fn(row) {
    let #(what, judged, conditions, passes, said) = row
    let verdict = load_judged.judge(judged:, conditions:)
    assert string.contains(verdict.summary, said) as what
    assert told(verdict:).0 == passes as what
  })
}
