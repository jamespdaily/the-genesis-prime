//// The counts a load run's gate judges, and the one rule that fails a run that saw too
//// few of them. A gate that judges what a run measured passes a run that measured nothing
//// unless each event it judges also has a minimum, so every merge-gating measure of
//// `genesis_prime/load_fight` and `genesis_prime/load_moves` goes through `judge`.
////
//// ```
//// each gate event's count and the scene's minimum ─▶ judge ─▶ Passes | Fails
//// a run's last line ─▶ require ─▶ the run's exit status 1 on Fails
//// ```
////
//// - An event is judged by a `Judged` naming it; its line holds its count and its minimum.
//// - The run fails when any event's count is below its minimum, and the summary names each.
//// - The minimum is the scene's: the fewest of the event that a run which measured the
////   gate's subject would have, so 0 is never enough (`test/code_rule/judged_count_test`
////   checks that every gate of the two runs is judged here).

import genesis_prime/dev_exit
import gleam/int
import gleam/list
import gleam/string

/// An event a load run's gate judges.
pub type Event {
  /// A strike round of a creature the walkers answered, as the recorder counted it.
  StrikeRounds
  /// A strike a walker answered.
  StrikeAnswers
  /// A removal of a unit and then its next creation, as a walker was sent them.
  Respawns
  /// A move of one probe that another probe read.
  MovesRead
}

/// Every event.
pub fn all() -> List(Event) {
  [StrikeRounds, StrikeAnswers, Respawns, MovesRead]
}

/// The event in words, as the run's lines name it.
pub fn name(event: Event) -> String {
  case event {
    StrikeRounds -> "strike rounds"
    StrikeAnswers -> "strike answers"
    Respawns -> "respawns"
    MovesRead -> "moves read by a probe"
  }
}

/// An event's count in a run and the fewest the scene needs.
pub type Judged {
  Judged(event: Event, count: Int, minimum: Int)
}

/// What the judged counts say of a run: the line of each count, and for a failure the
/// summary that names the events below their minimum.
pub type Verdict {
  Passes(lines: List(String))
  Fails(lines: List(String), summary: String)
}

/// The verdict on the judged counts: a run that has an event below its minimum fails.
pub fn judge(judged judged: List(Judged)) -> Verdict {
  let lines = list.map(judged, line)
  case list.filter(judged, below) {
    [] -> Passes(lines:)
    short ->
      Fails(
        lines:,
        summary: "fail: a judged count is below its minimum: "
          <> string.join(list.map(short, shortfall), ", "),
      )
  }
}

/// Ends the run with the exit status 1 when the verdict fails, after the run's lines are
/// written.
pub fn require(verdict verdict: Verdict) -> Nil {
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
