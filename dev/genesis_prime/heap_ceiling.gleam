//// The heap limit of each kind of process of prototype C: the map process and
//// a sender. It measures how large each gets under load, applies the choosing
//// rule to give a limit, and checks that a run at the limits kills nothing.
////
//// Run it with `gleam run -m genesis_prime/heap_ceiling` on a machine with
//// nothing else heavy running, and `gleam test` never runs it. The harness
//// process runs at high priority and runs on every core.
////
//// The parts, selected by naming them after `--` (none named runs `peaks`
//// then `check`):
////
//// - `peaks`: prototype C at `creature_count` creatures, each of
////   `player_counts` players and each of `visibility_ranges`, one full-length
////   run each. Each run prints the largest heap and mailbox of a map process
////   and of a sender, and the largest binary and ETS memory, from the heap
////   sampler. Then the choosing rule, `heap_limit.for_peak` on each kind's
////   largest peak over all the runs: it prints each limit in words and in
////   megabytes of 8-byte words, and how many maps at the map limit fit in a
////   gigabyte.
//// - `check`: prototype C at `check_players` players, one full-length run at
////   each of `visibility_ranges`, with the limits set; it prints each run's
////   kills and fails when a map process or a sender was killed.
////
//// `check` takes its limits from the `peaks` run when both run in one command.
//// Run alone it takes them after its name, as `check <map words> <sender
//// words>`, so the limits Jim approved are the ones checked.

import genesis_prime/topology/heap_limit.{type HeapLimit, type HeapLimits}
import genesis_prime/topology/run.{type RunResult}
import gleam/option.{type Option}

/// The creatures on the map in every run.
const creature_count = 10_000

/// The player counts of the `peaks` runs.
const player_counts = [100, 400, 800]

/// The visibility ranges of every run, in metres: 100 is the stand-in every
/// other run uses, 640 is the client's default draw distance
/// (`lod.viewDistance`, setting object 0x140c46410).
const visibility_ranges = [100.0, 640.0]

/// The player count of the `check` runs: the highest of `player_counts`.
const check_players = 800

/// Bytes in a megabyte as it is printed: 1,048,576.
const megabyte_bytes = 1_048_576

/// Bytes in a gigabyte as it is counted: 1,073,741,824.
const gigabyte_bytes = 1_073_741_824

/// Bytes in a word of the machines the server runs on.
const word_bytes = 8

/// What to run, from the arguments after `--`.
type Plan {
  /// The `peaks` part alone.
  PeaksOnly
  /// The `check` part alone, at the limits given after its name.
  CheckOnly(limits: HeapLimits)
  /// `peaks`, then `check` at the limits the rule chose from `peaks`.
  PeaksThenCheck
}

/// Why the arguments after `--` are not a plan.
type UsageError {
  /// A word that is neither `peaks` nor `check`.
  UnknownPart(word: String)
  /// `check` alone without two limits after it.
  CheckNeedsTwoLimits
  /// A limit that is not a whole number of words of at least 1.
  NotAWordCount(word: String)
}

/// One finished run of the `peaks` or `check` part.
type Found {
  Found(players: Int, visibility_range: Float, result: RunResult)
}

/// Runs the parts named after `--`, or all of them, and prints what they
/// found. A bad argument prints what the arguments may be and stops. Every
/// core is online again at the end.
pub fn main() -> Nil {
  todo as "body in the build commit"
}

/// The plan the arguments after `--` name.
fn plan_from(arguments: List(String)) -> Result(Plan, UsageError) {
  todo as "body in the build commit"
}

/// The `peaks` part: one full-length run for each of `player_counts` and each
/// of `visibility_ranges`, each printed as it finishes with its sampled peaks.
fn peaks() -> List(Found) {
  todo as "body in the build commit"
}

/// The choosing rule over the `peaks` runs: `heap_limit.for_peak` on the
/// largest map peak and on the largest sender peak over all the runs.
fn chosen_limits(found: List(Found)) -> HeapLimits {
  todo as "body in the build commit"
}

/// Prints the limits in words and in megabytes, and how many maps at the map
/// limit fit in a gigabyte.
fn print_limits(limits: HeapLimits) -> Nil {
  todo as "body in the build commit"
}

/// How many maps of the limit fit in a gigabyte, or none for no limit.
fn maps_per_gigabyte(limit: HeapLimit) -> Option(Int) {
  todo as "body in the build commit"
}

/// The `check` part: one full-length run at `check_players` players for each
/// of `visibility_ranges` with `limits` set. Prints each run's kills and
/// fails when any run killed a map process or a sender.
fn check(limits: HeapLimits) -> List(Found) {
  todo as "body in the build commit"
}
