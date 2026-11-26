//// What the load runs' judged counts say, from planted counts: a gate that decides a
//// merge must fail a run that saw none of the events it judges (one run passed with no
//// strike round measured, another with no respawn seen), one that judged nothing, and one
//// whose other condition (the map keeping up, the step's verdict) did not hold. The wording
//// is the shared function's (`genesis_prime/load_judged`): the event's name, its count, its
//// minimum.

import genesis_prime/load_judged.{
  type Verdict, CastEndsRead, CastStartsRead, CastsHeld, Condition, Fails,
  Judged, MovesRead, Passes, PlayersShown, RemovalsRead, Respawns, StrikeAnswers,
  StrikeRounds,
}
import gleam/list
import gleam/option.{None, Some}
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

pub fn a_run_that_lost_an_answer_to_the_deadline_fails_as_a_whole_and_one_that_lost_none_holds_its_condition_test() -> Nil {
  use <- owned_test.run(5000)
  let seen = Judged(event: StrikeRounds, count: 4, minimum: 1)
  let none_lost = load_judged.nothing_lost(lost: 0)
  assert none_lost.held as "no answer lost holds the condition"
  assert none_lost.said == "no answer was lost to the deadline" as "and says so"
  let three_lost = load_judged.nothing_lost(lost: 3)
  assert !three_lost.held as "three answers lost do not hold it"
  assert string.contains(three_lost.said, "3")
    as "and the sentence says how many"
  let held = load_judged.judge(judged: [seen], conditions: [none_lost])
  assert told(verdict: held).0 as "every count enough and none lost passes"
  let lost = load_judged.judge(judged: [seen], conditions: [three_lost])
  assert !told(verdict: lost).0 as "three lost fails the run as a whole"
  assert string.contains(lost.summary, three_lost.said)
    as "and the summary names the lost count"
}

pub fn a_run_that_showed_fewer_players_than_pairs_a_map_that_falls_behind_and_a_delay_past_its_guard_each_fail_and_a_run_that_holds_all_three_passes_test() -> Nil {
  use <- owned_test.run(5000)
  // 100 walkers and 4 probes: (100 + 4) x (104 - 1) = 10,712 pairs. The map is sampled
  // 1,000 times; a mean queue of one round of moves is as long as the players are many.
  let pairs = 10_712
  let shown = fn(count) { Judged(event: PlayersShown, count:, minimum: pairs) }
  let map = fn(queued, running) {
    load_judged.map_keeps_up(queued:, samples: 1000, running:, players: 104)
  }
  // The paired main run's 99th percentile, in microseconds.
  let baseline = Some(30_000)
  let guarded = fn(p99_us) {
    load_judged.delay_within_guard(p99_us:, baseline_p99_us: baseline)
  }
  let rows = [
    #(
      "every pair shown, the map keeping up, the delay at the guard, no frame after a removal",
      [shown(pairs)],
      [
        map(100_000, 100),
        guarded(80_000),
        load_judged.no_frame_after_removal(violations: 0, removals: 400),
      ],
      True,
      "pass: the map keeps up",
    ),
    #(
      "one pair fewer than the players owe",
      [shown(pairs - 1)],
      [],
      False,
      "players shown 10711 of at least 10712",
    ),
    #(
      "a mean queue of one round of moves",
      [shown(pairs)],
      [map(104_000, 100)],
      False,
      "the map falls behind",
    ),
    #(
      "a mean queue a move below one round",
      [shown(pairs)],
      [map(103_999, 100)],
      True,
      "the map keeps up",
    ),
    #(
      "a map running in half of the samples",
      [shown(pairs)],
      [map(100, 500)],
      False,
      "the map falls behind",
    ),
    #(
      "a map running in just under half of the samples",
      [shown(pairs)],
      [map(100, 499)],
      True,
      "the map keeps up",
    ),
    #(
      "a delay the baseline plus 50 ms",
      [shown(pairs)],
      [guarded(80_000)],
      True,
      "within 50 ms of the baseline",
    ),
    #(
      "a delay the baseline plus 51 ms",
      [shown(pairs)],
      [guarded(81_000)],
      False,
      "more than 50 ms above the baseline",
    ),
    #(
      "no baseline given: the delay is printed and not judged, however long",
      [shown(pairs)],
      [load_judged.delay_within_guard(p99_us: 900_000, baseline_p99_us: None)],
      True,
      "the delay is printed and not judged: no baseline was given",
    ),
    #(
      "a frame read after a removal",
      [shown(pairs)],
      [load_judged.no_frame_after_removal(violations: 2, removals: 400)],
      False,
      "frames were read after their unit's removal: 2",
    ),
    #(
      "no frame after a removal, and no removal read, is no order checked",
      [shown(pairs)],
      [load_judged.no_frame_after_removal(violations: 0, removals: 0)],
      False,
      "no removal was read, so no frame was checked against one",
    ),
    #(
      "a map that was never sampled is not known to keep up",
      [shown(pairs)],
      [
        load_judged.map_keeps_up(
          queued: 0,
          samples: 0,
          running: 0,
          players: 104,
        ),
      ],
      False,
      "the map was never sampled",
    ),
    #(
      "cast starts below the probes' casts owed",
      [Judged(event: CastStartsRead, count: 7, minimum: 8)],
      [],
      False,
      "cast starts read by a probe 7 of at least 8",
    ),
    #(
      "cast starts as owed and every cast end lost",
      [
        Judged(event: CastStartsRead, count: 8, minimum: 8),
        Judged(event: CastEndsRead, count: 0, minimum: 8),
      ],
      [],
      False,
      "cast ends read by a probe 0 of at least 8",
    ),
    #(
      "cast starts and ends as owed",
      [
        Judged(event: CastStartsRead, count: 8, minimum: 8),
        Judged(event: CastEndsRead, count: 8, minimum: 8),
      ],
      [],
      True,
      "pass: every judged count is at or above its minimum",
    ),
    #(
      "casts cut short are not held, whatever the frames read",
      [
        Judged(event: CastStartsRead, count: 8, minimum: 8),
        Judged(event: CastsHeld, count: 3, minimum: 8),
      ],
      [],
      False,
      "casts held by a probe's read 3 of at least 8",
    ),
    #(
      "removals below the probes' leaving",
      [Judged(event: RemovalsRead, count: 399, minimum: 400)],
      [],
      False,
      "removals read by a walker 399 of at least 400",
    ),
  ]
  list.each(rows, fn(row) {
    let #(what, judged, conditions, passes, said) = row
    let verdict = load_judged.judge(judged:, conditions:)
    assert string.contains(verdict.summary, said) as what
    assert told(verdict:).0 == passes as what
  })
}
