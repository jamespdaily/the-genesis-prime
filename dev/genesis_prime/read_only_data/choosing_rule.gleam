//// The choosing rule, as amended on the issue, run on measured standings and
//// printed step by step:
////
//// 1. A variant holding more than 100 MB more memory than the lowest (for the
////    three tables, with 4 holder processes) is out.
//// 2. A variant loading more than 5 s slower than the fastest is out.
//// 3. Of those left, the lowest read cost wins, unless others are within 220
////    ns per read of it (1% of a map message's 22 us); then of those, the one
////    with the lowest memory wins.
////
//// Megabytes are 1,000,000 bytes.

/// What the rule needs to know about one variant.
pub type Standing {
  Standing(
    variant: String,
    /// The bytes the variant holds for the three tables.
    memory_bytes: Int,
    /// The median time to load the three tables.
    load_milliseconds: Float,
    /// The median time of one read.
    read_nanoseconds: Float,
  )
}

/// A variant dropped at one step, and why.
pub type Dropped {
  Dropped(variant: String, reason: String)
}

/// What one step left and dropped.
pub type Step {
  Step(title: String, left: List(Standing), dropped: List(Dropped))
}

/// The three steps and the variant they end on.
pub type Choice {
  Choice(steps: List(Step), winner: Standing)
}

/// Runs the three steps on `standings`, which hold at least one. The winner
/// is always one of them: the lowest memory and the fastest load are never
/// dropped by the steps that compare against them.
pub fn choose(standings: List(Standing)) -> Choice {
  todo as "body in the build commit"
}

/// Prints each step's title, who it dropped with the reason, who was left, and
/// the winner.
pub fn print(choice: Choice) -> Nil {
  todo as "body in the build commit"
}
