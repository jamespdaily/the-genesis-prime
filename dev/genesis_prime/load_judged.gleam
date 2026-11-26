//// The counts a load run's gate judges, and the one rule that fails a run that saw too
//// few of them. A gate that judges what a run measured passes a run that measured nothing
//// unless each event it judges also has a minimum, so every merge-gating measure of
//// `genesis_prime/load_fight` and `genesis_prime/load_moves` goes through `judge`.
////
//// ```
//// each gate event's count and the scene's minimum ─┐
//// each other condition the run needs ──────────────┴▶ judge ─▶ Passes | Fails
//// the verdict ─▶ require ─▶ prints the summary, exit status 1 on Fails
//// ```
////
//// - An event is judged by a `Judged` naming it; its line holds its count and its minimum.
//// - The run fails when any event's count is below its minimum, and the summary names each.
//// - A condition that is not a count (the map keeping up, the step's verdict) is a
////   `Condition`; one not held fails the run, so every verdict of a run is this module's
////   (`test/code_rule/judged_count_test` refuses a verdict line in the two tools).
//// - A run that judges no event fails: it measured nothing.
//// - The minimum is the scene's: the fewest of the event that a run which measured the
////   gate's subject would have, so 0 is never enough (`test/code_rule/judged_count_test`
////   checks that every gate of the two runs is judged here).

import genesis_prime/dev_exit
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// An event a load run's gate judges.
pub type Event {
  /// A strike round of a creature the walkers answered, as the recorder counted it.
  StrikeRounds
  /// A strike a walker answered.
  StrikeAnswers
  /// A strike a walker made that a creature answered with `Struck`.
  StrikesAnswered
  /// A removal of a unit and then its next creation, as a walker was sent them.
  Respawns
  /// A move of one probe that another probe read.
  MovesRead
  /// A player's 0x262 that a walker or a probe read, one for each other player.
  PlayersShown
  /// A 0x7ff or 0x7fe of another player's cast that a probe read.
  CastFramesRead
}

/// Every event.
pub fn all() -> List(Event) {
  [
    StrikeRounds,
    StrikeAnswers,
    StrikesAnswered,
    Respawns,
    MovesRead,
    PlayersShown,
    CastFramesRead,
  ]
}

/// The event in words, as the run's lines name it.
pub fn name(event: Event) -> String {
  case event {
    StrikeRounds -> "strike rounds"
    StrikeAnswers -> "strike answers"
    StrikesAnswered -> "strikes answered"
    Respawns -> "respawns"
    MovesRead -> "moves read by a probe"
    PlayersShown -> "players shown"
    CastFramesRead -> "cast frames read by a probe"
  }
}

/// An event's count in a run and the fewest the scene needs.
pub type Judged {
  Judged(event: Event, count: Int, minimum: Int)
}

/// A condition of a run that is not a count: whether it held, and the sentence for the
/// state it is in.
pub type Condition {
  Condition(held: Bool, said: String)
}

/// What the judged counts and conditions say of a run: the line of each count, and the
/// summary line, which names what failed.
pub type Verdict {
  Passes(lines: List(String), summary: String)
  Fails(lines: List(String), summary: String)
}

/// The condition that no answer was lost to a deadline: `lost` is how many answers were
/// sent before their round's deadline fell due and the round closed without them
/// (`genesis_prime/load_round`).
pub fn nothing_lost(lost lost: Int) -> Condition {
  case lost {
    0 -> Condition(held: True, said: "no answer was lost to the deadline")
    _ ->
      Condition(
        held: False,
        said: "answers were lost to the deadline: "
          <> int.to_string(lost)
          <> " sent before it fell due, and their round closed without them",
      )
  }
}

/// The condition that the map keeps up: the stub of its rule.
pub fn map_keeps_up(
  queued _queued: Int,
  samples _samples: Int,
  running _running: Int,
  players _players: Int,
) -> Condition {
  Condition(held: True, said: "")
}

/// The condition that the delay's 99th percentile is within the guard of the paired
/// baseline run's: the stub of its rule.
pub fn delay_within_guard(
  p99_us _p99_us: Int,
  baseline_p99_us _baseline_p99_us: Option(Int),
) -> Condition {
  Condition(held: True, said: "")
}

/// The condition that no unit's frame was read after its removal: the stub of its rule.
pub fn no_frame_after_removal(violations _violations: Int) -> Condition {
  Condition(held: True, said: "")
}

/// The verdict on a run: it fails when an event is below its minimum, when a condition is
/// not held, or when it judged no event.
pub fn judge(
  judged judged: List(Judged),
  conditions conditions: List(Condition),
) -> Verdict {
  let lines = list.map(judged, line)
  let reasons =
    list.flatten([
      case judged {
        [] -> ["nothing was judged"]
        [_, ..] -> []
      },
      case list.filter(judged, below) {
        [] -> []
        short -> [
          "a judged count is below its minimum: "
          <> string.join(list.map(short, shortfall), ", "),
        ]
      },
      list.filter(conditions, fn(condition) { !condition.held })
        |> list.map(fn(condition) { condition.said }),
    ])
  case reasons {
    [] ->
      Passes(
        lines:,
        summary: "pass: "
          <> string.join(
          list.append(list.map(conditions, fn(condition) { condition.said }), [
            "every judged count is at or above its minimum",
          ]),
          "; ",
        ),
      )
    [_, ..] -> Fails(lines:, summary: "fail: " <> string.join(reasons, "; "))
  }
}

/// Prints the verdict's summary and ends the run with the exit status 1 when the verdict
/// fails, after the run's lines are written.
pub fn require(verdict verdict: Verdict) -> Nil {
  io.println(verdict.summary)
  case verdict {
    Passes(..) -> Nil
    Fails(..) -> dev_exit.halt(1)
  }
}

fn below(judged: Judged) -> Bool {
  judged.count < judged.minimum
}

fn line(judged: Judged) -> String {
  name(judged.event)
  <> ": "
  <> int.to_string(judged.count)
  <> case below(judged) {
    True -> ", below its minimum of " <> int.to_string(judged.minimum)
    False -> " (minimum " <> int.to_string(judged.minimum) <> ")"
  }
}

fn shortfall(judged: Judged) -> String {
  name(judged.event)
  <> " "
  <> int.to_string(judged.count)
  <> " of at least "
  <> int.to_string(judged.minimum)
}
