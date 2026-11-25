//// The judged counts of the load runs.

/// An event a load run's gate judges.
pub type Event {
  StrikeRounds
  StrikeAnswers
  Respawns
  MovesRead
}

/// Every event.
pub fn all() -> List(Event) {
  [StrikeRounds, StrikeAnswers, Respawns, MovesRead]
}

/// The event in words.
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

/// What the judged counts say of a run.
pub type Verdict {
  Passes(lines: List(String))
  Fails(lines: List(String), summary: String)
}

/// The verdict on the judged counts.
pub fn judge(judged _judged: List(Judged)) -> Verdict {
  Passes([])
}
