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
//// Megabytes are 1,000,000 bytes. Step 2 compares load times among the
//// variants step 1 left.

import genesis_prime/topology/trial
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

/// Step 1: how many bytes more than the lowest memory a variant may hold.
const memory_margin_bytes = 100_000_000

/// Step 2: how many milliseconds slower than the fastest load a variant may
/// load.
const load_margin_milliseconds = 5000.0

/// Step 3: how many nanoseconds above the lowest read cost still count as a
/// tie (1% of a map message's 22 us).
const read_tie_nanoseconds = 220.0

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

/// Runs the three steps on `standings`, which hold at least one. The steps
/// never leave none: each keeps the variant it measures the others against.
pub fn choose(standings: List(Standing)) -> Choice {
  let by_memory =
    narrow(
      title: "1. memory: out when more than 100 MB above the lowest",
      standings:,
      measure: fn(standing) { int.to_float(standing.memory_bytes) },
      allowed_above: int.to_float(memory_margin_bytes),
      reason: fn(standing, lowest) {
        megabytes(standing.memory_bytes)
        <> " MB is "
        <> megabytes(standing.memory_bytes - float.round(lowest))
        <> " MB above the lowest, "
        <> megabytes(float.round(lowest))
        <> " MB"
      },
    )
  let by_load =
    narrow(
      title: "2. load time: out when more than 5 s slower than the fastest left",
      standings: by_memory.left,
      measure: fn(standing) { standing.load_milliseconds },
      allowed_above: load_margin_milliseconds,
      reason: fn(standing, lowest) {
        trial.two_places(standing.load_milliseconds)
        <> " ms is "
        <> trial.two_places(standing.load_milliseconds -. lowest)
        <> " ms above the fastest, "
        <> trial.two_places(lowest)
        <> " ms"
      },
    )
  let by_read =
    narrow(
      title: "3. read cost: those within 220 ns of the lowest stay; the lowest memory of them wins",
      standings: by_load.left,
      measure: fn(standing) { standing.read_nanoseconds },
      allowed_above: read_tie_nanoseconds,
      reason: fn(standing, lowest) {
        trial.two_places(standing.read_nanoseconds)
        <> " ns is "
        <> trial.two_places(standing.read_nanoseconds -. lowest)
        <> " ns above the lowest, "
        <> trial.two_places(lowest)
        <> " ns"
      },
    )
  let assert [winner, ..] =
    list.sort(by_read.left, fn(a, b) {
      int.compare(a.memory_bytes, b.memory_bytes)
    })
    as "the steps leave at least one variant"
  Choice(steps: [by_memory, by_load, by_read], winner:)
}

/// Prints each step's title, who it dropped with the reason, who was left, and
/// the winner.
pub fn print(choice: Choice) -> Nil {
  list.each(choice.steps, fn(step) {
    io.println(step.title)
    case step.dropped {
      [] -> io.println("   none dropped")
      dropped ->
        list.each(dropped, fn(found) {
          io.println("   out: " <> found.variant <> ": " <> found.reason)
        })
    }
    io.println(
      "   left: "
      <> string.join(
        list.map(step.left, fn(standing) { standing.variant }),
        ", ",
      ),
    )
  })
  io.println(
    "   winner: "
    <> choice.winner.variant
    <> " ("
    <> megabytes(choice.winner.memory_bytes)
    <> " MB, load "
    <> trial.two_places(choice.winner.load_milliseconds)
    <> " ms, read "
    <> trial.two_places(choice.winner.read_nanoseconds)
    <> " ns)",
  )
}

/// Keeps the standings whose `measure` is at most `allowed_above` over the
/// lowest `measure` among them, and drops the rest with `reason`.
fn narrow(
  title title: String,
  standings standings: List(Standing),
  measure measure: fn(Standing) -> Float,
  allowed_above allowed_above: Float,
  reason reason: fn(Standing, Float) -> String,
) -> Step {
  let assert Ok(lowest) = list.reduce(list.map(standings, measure), float.min)
    as "a step is given at least one standing"
  let #(left, far) =
    list.partition(standings, fn(standing) {
      measure(standing) -. lowest <=. allowed_above
    })
  Step(
    title:,
    left:,
    dropped: list.map(far, fn(standing) {
      Dropped(variant: standing.variant, reason: reason(standing, lowest))
    }),
  )
}

/// Bytes as megabytes of 1,000,000 bytes, to two places.
fn megabytes(bytes: Int) -> String {
  trial.two_places(int.to_float(bytes) /. 1_000_000.0)
}
