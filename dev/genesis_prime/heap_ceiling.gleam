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
////   kills and replacements, counted from the start of the run, and fails when
////   a map process or a sender was killed or replaced for any reason.
////
//// `check` takes its limits from the `peaks` run when both run in one command.
//// Run alone it takes them after its name, as `check <map words> <sender
//// words>`, so the limits Jim approved are the ones checked.

import genesis_prime/topology/heap_limit.{type HeapLimit, type HeapLimits}
import genesis_prime/topology/heap_sampler.{type Sampled}
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/run.{type RunResult}
import genesis_prime/topology/trial
import genesis_prime/topology/workload.{Workload}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/result

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
  case plan_from(measurement.plain_arguments()) {
    Error(error) -> io.println_error(usage_text(error))
    Ok(plan) -> {
      measurement.set_high_priority()
      measurement.enable_scheduler_wall_time()
      case plan {
        PeaksOnly -> {
          let found = peaks()
          print_limits(chosen_limits(found))
        }
        PeaksThenCheck -> {
          let found = peaks()
          let limits = chosen_limits(found)
          print_limits(limits)
          let _checked = check(limits)
          Nil
        }
        CheckOnly(limits:) -> {
          print_limits(limits)
          let _checked = check(limits)
          Nil
        }
      }
      measurement.set_schedulers_online(measurement.core_count())
    }
  }
}

/// What the arguments may be, and which one was wrong.
fn usage_text(error: UsageError) -> String {
  let problem = case error {
    UnknownPart(word:) -> "unknown part: " <> word
    CheckNeedsTwoLimits -> "check alone needs two limits after it"
    NotAWordCount(word:) ->
      "not a whole number of words of at least 1: " <> word
  }
  problem
  <> "\nusage: gleam run -m genesis_prime/heap_ceiling [-- peaks [check]]"
  <> "\n       gleam run -m genesis_prime/heap_ceiling -- check <map words> <sender words>"
}

/// The plan the arguments after `--` name.
fn plan_from(arguments: List(String)) -> Result(Plan, UsageError) {
  case arguments {
    [] | ["peaks", "check"] -> Ok(PeaksThenCheck)
    ["peaks"] -> Ok(PeaksOnly)
    ["check", map_word, sender_word] -> {
      use map <- result.try(limit_from(map_word))
      use sender <- result.try(limit_from(sender_word))
      Ok(CheckOnly(limits: heap_limit.HeapLimits(map:, sender:)))
    }
    ["check", ..] -> Error(CheckNeedsTwoLimits)
    ["peaks", other, ..] -> Error(UnknownPart(word: other))
    [other, ..] -> Error(UnknownPart(word: other))
  }
}

/// A limit from the word count written as text.
fn limit_from(word: String) -> Result(HeapLimit, UsageError) {
  int.parse(word)
  |> result.try(fn(count) { heap_limit.words(count) })
  |> result.replace_error(NotAWordCount(word:))
}

/// The `peaks` part: one full-length run for each of `player_counts` and each
/// of `visibility_ranges`, each printed as it finishes with its sampled peaks.
fn peaks() -> List(Found) {
  io.println(
    "\n== peaks: prototype C, "
    <> int.to_string(creature_count)
    <> " creatures, no heap limit",
  )
  list.flat_map(visibility_ranges, fn(visibility_range) {
    list.map(player_counts, fn(players) {
      run_found(players:, visibility_range:, limits: heap_limit.no_limits)
    })
  })
}

/// One full-length run of prototype C at `limits`, with the heap sampler on,
/// printed as it finishes.
fn run_found(
  players players: Int,
  visibility_range visibility_range: Float,
  limits limits: HeapLimits,
) -> Found {
  let result =
    run.run(
      prototype: run.MapProcess(map_process.SenderPool, limits),
      workload: Workload(
        ..workload.default(),
        players:,
        creatures: creature_count,
        visibility_range:,
      ),
      maps: 1,
      schedulers: measurement.core_count(),
      timing: run.full_timing,
      sampling: run.SampleHeaps,
    )
  let found = Found(players:, visibility_range:, result:)
  print_found(found)
  found
}

/// What the heap sampler found in a run; a run of `heap_ceiling` always
/// samples.
fn sampled_of(found: Found) -> Sampled {
  let assert option.Some(sampled) = found.result.sampled
    as "a run of the heap ceiling samples heaps"
  sampled
}

/// One run as a line: the sampled peaks of each kind, the runtime's binary and
/// ETS memory, how many processes the runtime killed, how many were replaced
/// and the pace.
fn print_found(found: Found) -> Nil {
  let sampled = sampled_of(found)
  io.println(
    trial.pad_start(text: int.to_string(found.players), width: 5)
    <> " players range "
    <> trial.pad_start(text: trial.two_places(found.visibility_range), width: 7)
    <> " m: map heap "
    <> int.to_string(sampled.map.heap_words)
    <> " words, queue "
    <> int.to_string(sampled.map.queue)
    <> "; sender heap "
    <> int.to_string(sampled.sender.heap_words)
    <> " words, queue "
    <> int.to_string(sampled.sender.queue)
    <> "; binary "
    <> int.to_string(sampled.binary_bytes)
    <> " bytes, ets "
    <> int.to_string(sampled.ets_bytes)
    <> " bytes; killed maps "
    <> int.to_string(sampled.killed.maps)
    <> " senders "
    <> int.to_string(sampled.killed.senders)
    <> "; replaced maps "
    <> int.to_string(sampled.replaced.maps)
    <> " senders "
    <> int.to_string(sampled.replaced.senders)
    <> "; "
    <> trial.pace_name(found.result.pace),
  )
}

/// The largest map heap and the largest sender heap over `found`, in words.
fn largest_peaks(found: List(Found)) -> #(Int, Int) {
  #(
    list.fold(found, 0, fn(largest, one) {
      int.max(largest, sampled_of(one).map.heap_words)
    }),
    list.fold(found, 0, fn(largest, one) {
      int.max(largest, sampled_of(one).sender.heap_words)
    }),
  )
}

/// The choosing rule over the `peaks` runs: `heap_limit.for_peak` on the
/// largest map peak and on the largest sender peak over all the runs.
fn chosen_limits(found: List(Found)) -> HeapLimits {
  let #(map_peak, sender_peak) = largest_peaks(found)
  io.println(
    "\n== choosing rule: four times the largest peak, rounded up to a power of two"
    <> "\nlargest map heap "
    <> int.to_string(map_peak)
    <> " words, largest sender heap "
    <> int.to_string(sender_peak)
    <> " words",
  )
  heap_limit.HeapLimits(
    map: heap_limit.for_peak(map_peak),
    sender: heap_limit.for_peak(sender_peak),
  )
}

/// Prints the limits in words and in megabytes, and how many maps at the map
/// limit fit in a gigabyte.
fn print_limits(limits: HeapLimits) -> Nil {
  io.println(
    "map limit: "
    <> limit_text(limits.map)
    <> "; maps of that limit in 1 GB: "
    <> case maps_per_gigabyte(limits.map) {
      option.Some(count) -> int.to_string(count)
      option.None -> "no limit"
    },
  )
  io.println("sender limit: " <> limit_text(limits.sender))
}

/// A limit as words and megabytes of `word_bytes`-byte words, or "no limit".
fn limit_text(limit: HeapLimit) -> String {
  case heap_limit.to_words(limit) {
    option.None -> "no limit"
    option.Some(words) ->
      int.to_string(words)
      <> " words, "
      <> trial.two_places(
        int.to_float(words * word_bytes) /. int.to_float(megabyte_bytes),
      )
      <> " MB"
  }
}

/// How many maps of the limit fit in a gigabyte, or none for no limit.
fn maps_per_gigabyte(limit: HeapLimit) -> Option(Int) {
  heap_limit.to_words(limit)
  |> option.map(fn(words) { gigabyte_bytes / { words * word_bytes } })
}

/// The `check` part: one full-length run at `check_players` players for each
/// of `visibility_ranges` with `limits` set. Prints each run's kills and
/// replacements and fails when any run killed or replaced a map process or a
/// sender, whether in the warm-up or the measured stretch. The monitor counts a
/// kill, and the replacement count catches a process that ended for another
/// reason or that the monitor missed.
fn check(limits: HeapLimits) -> List(Found) {
  io.println(
    "\n== check: prototype C, "
    <> int.to_string(creature_count)
    <> " creatures, "
    <> int.to_string(check_players)
    <> " players, at the limits",
  )
  let found =
    list.map(visibility_ranges, fn(visibility_range) {
      run_found(players: check_players, visibility_range:, limits:)
    })
  assert list.all(found, fn(one) {
    let sampled = sampled_of(one)
    sampled.killed == heap_sampler.Killed(maps: 0, senders: 0)
    && sampled.replaced == heap_sampler.Replaced(maps: 0, senders: 0)
  })
    as "a map process or a sender was killed or replaced at the chosen limits"
  io.println("no map process and no sender was killed or replaced")
  found
}
