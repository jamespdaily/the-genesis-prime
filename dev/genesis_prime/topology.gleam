//// Which process owns a unit's state: one process per unit with its position
//// in a shared table (A), one process that owns the whole map and sends its
//// own updates (B), or that process with the sending handed to a pool of
//// sender processes (C). The three prototypes run the same game rules under
//// the same load, and only the ownership and the sending differ.
////
//// Run it with `gleam run -m genesis_prime/topology` on a machine with
//// nothing else heavy running. It lives in `dev/` because Gleam compiles that
//// directory with the project, so `gleam build` keeps it compiling, while
//// `gleam test` never runs it. It uses only the runtime's own counters, so it
//// can be run again on the real map.
////
//// It runs its parts in order and prints a table for each, then the
//// prototype the choosing rule picks. Correctness is the test suite:
//// `gleam test` must pass before these numbers count. Every run has 10,000
//// creatures. The parts, selected by naming them after `--` (none named runs
//// all of them):
////
//// - `all-cores`: every core, visibility ranges 100 m and 640 m, player
////   counts counted up with short runs until a prototype falls behind, then the
////   count below that and the count that fell behind rerun at full length.
//// - `one-core`: one scheduler, 100 m, 100 and 400 players, short runs.
//// - `time`: scheduler busy time per message, in paired short rounds.
//// - `crash`: the time from an owner's death to its rebuilt process answering.
//// - the choosing rule, which runs after `all-cores` and `time` when both ran.

import genesis_prime/topology/latency
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/per_unit
import genesis_prime/topology/run.{type Prototype, type RunResult, type Timing}
import genesis_prime/topology/workload.{type Workload, Workload}
import gleam/dict
import gleam/erlang/reference
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/string

/// The three prototypes, in the order they are run and printed.
const prototypes = [
  run.PerUnit,
  run.MapProcess(map_process.SendsItself),
  run.MapProcess(map_process.SenderPool),
]

/// The creatures on the map in every run.
const creature_count = 10_000

/// The player counts the all-cores climb goes through, lowest first.
const player_counts = [100, 200, 400, 800]

/// The visibility ranges of the all-cores part, in metres. 100 is the stand-in
/// every other run uses; 640 is the client's default draw distance
/// (`lod.viewDistance`, setting object 0x140c46410), which bounds what a
/// player can see.
const visibility_ranges = [100.0, 640.0]

/// The player counts of the one-core part, at the default visibility range.
const one_core_player_counts = [100, 400]

/// How many paired rounds the time per message is taken over; the median
/// counts.
const time_rounds = 5

/// The player count at which latency, time per message and memory are
/// compared by the choosing rule, at `creature_count` creatures and the
/// default visibility range.
const comparison_players = 100

/// Choosing rule, first step: a prototype that did not keep up at this many
/// players on all cores, at every visibility range in `visibility_ranges`, is
/// out.
const ceiling_floor_players = 400

/// Choosing rule, second step: a difference in 99th-percentile latency of at
/// least this many microseconds decides for the lower. It is a tenth of the
/// client's movement send interval, 125 ms (0x140c3a004).
const latency_tie_microseconds = 12_500

/// Choosing rule, third step: a prototype whose scheduler busy time per
/// message is lower by more than this percent of the other's wins; a smaller
/// difference is below what the harness can resolve between two runs of the
/// same prototype, measured by pairing runs with a cost planted in them.
const resolution_percent = 5.0

/// How many times the crash cost of each prototype is timed.
const crash_repeats = 3

/// The parts of the run, in the order they run.
const parts = ["all-cores", "one-core", "time", "crash"]

/// Runs the parts named after `--`, or all of them, in order, and prints their
/// tables and the choosing rule's pick.
pub fn main() -> Nil {
  todo as "body in the build commit"
}

/// Where one prototype stopped keeping up at one visibility range, from the
/// full-length confirmation runs only. A run whose owners kept up but whose
/// players did not all report counts as kept up.
type Ceiling {
  Ceiling(
    prototype: Prototype,
    visibility_range: Float,
    /// The highest player count whose confirmation run kept up, or none when
    /// no confirmation run kept up.
    kept_up_at: Option(Int),
    /// The lowest player count whose confirmation run fell behind, or none
    /// when none did.
    fell_behind_at: Option(Int),
  )
}

/// What the all-cores part found: the short runs of every climb, the
/// full-length confirmation runs, and each prototype's ceiling at each range.
type AllCores {
  AllCores(
    climbed: List(RunResult),
    confirmed: List(RunResult),
    ceilings: List(Ceiling),
  )
}

/// The all-cores part: for each visibility range and prototype, the climb and
/// its confirmation. Prints the latency, ceiling and memory tables.
fn all_cores(schedulers schedulers: Int) -> AllCores {
  todo as "body in the build commit"
}

/// Short runs of one prototype at each player count of `player_counts`, lowest
/// first, stopping after the first run that fell behind; the runs, in the
/// order they ran. Owners that kept up with every count give every count's run.
fn climb(
  prototype prototype: Prototype,
  visibility_range visibility_range: Float,
  schedulers schedulers: Int,
) -> List(RunResult) {
  todo as "body in the build commit"
}

/// Full-length reruns of the highest player count of `climbed` that kept up
/// and the first that fell behind, each when there is one.
fn confirm(
  climbed climbed: List(RunResult),
  visibility_range visibility_range: Float,
  schedulers schedulers: Int,
) -> List(RunResult) {
  todo as "body in the build commit"
}

/// The ceiling `confirmed`, the confirmation runs of one prototype at one
/// range, show.
fn ceiling_of(
  prototype prototype: Prototype,
  visibility_range visibility_range: Float,
  confirmed confirmed: List(RunResult),
) -> Ceiling {
  todo as "body in the build commit"
}

/// Whether the prototype kept up at `players` players at the ceiling's range:
/// its highest confirmed player count that kept up reaches `players`.
fn keeps_up_at(ceiling ceiling: Ceiling, players players: Int) -> Bool {
  todo as "body in the build commit"
}

/// The one-core part: `one_core_player_counts` for each prototype, short runs
/// on one scheduler at the default visibility range. Prints the latency and
/// ceiling tables.
fn one_core() -> Nil {
  todo as "body in the build commit"
}

fn workload_for(
  players players: Int,
  visibility_range visibility_range: Float,
) -> Workload {
  Workload(
    ..workload.default(),
    players:,
    creatures: creature_count,
    visibility_range:,
  )
}

/// One run with the given timing, printed as it finishes.
fn measured_run(
  prototype prototype: Prototype,
  workload workload: Workload,
  schedulers schedulers: Int,
  timing timing: Timing,
) -> RunResult {
  let result = run.run(prototype, workload, schedulers, timing)
  io.println(
    string.pad_end(run.name_of(prototype), 32, " ")
    <> pad_start(int.to_string(workload.players), 5)
    <> " players "
    <> pad_start(int.to_string(workload.creatures), 6)
    <> " creatures range "
    <> pad_start(two_places(workload.visibility_range), 7)
    <> ": p50 "
    <> pad_start(int.to_string(latency.percentile(result.latency, 50.0)), 8)
    <> " p99 "
    <> pad_start(int.to_string(latency.percentile(result.latency, 99.0)), 8)
    <> " max "
    <> pad_start(int.to_string(latency.maximum(result.latency)), 8)
    <> " us, moves "
    <> int.to_string(result.moves_sent)
    <> " updates "
    <> int.to_string(result.updates_received)
    <> " queues "
    <> int.to_string(list.fold(result.queue_samples, 0, int.max))
    <> " (largest) "
    <> pace_name(result),
  )
  result
}

/// Prints microseconds from a move's send to its arrival at a player in range,
/// for each of `runs`.
fn print_latency(schedulers: Int, runs: List(RunResult)) -> Nil {
  todo as "body in the build commit"
}

/// Prints each ceiling: the highest player count that kept up and the lowest
/// that fell behind, in the full-length confirmation runs.
fn print_ceiling(schedulers: Int, ceilings: List(Ceiling)) -> Nil {
  todo as "body in the build commit"
}

/// Prints the words of memory per unit of each of `runs`.
fn print_memory(schedulers: Int, runs: List(RunResult)) -> Nil {
  todo as "body in the build commit"
}

fn pace_name(result: RunResult) -> String {
  case result.pace {
    run.KeptUp -> "KeptUp"
    run.FellBehind -> "FellBehind"
    run.PlayersFellBehind -> "PlayersFellBehind"
  }
}

fn sorted_by_creatures_and_players(runs: List(RunResult)) -> List(RunResult) {
  list.sort(runs, fn(a, b) {
    case int.compare(a.creatures, b.creatures) {
      order.Eq -> int.compare(a.players, b.players)
      other -> other
    }
  })
}

fn prototypes_in(runs: List(RunResult)) -> List(Prototype) {
  list.fold(runs, [], fn(found, result) {
    case list.contains(found, result.prototype) {
      True -> found
      False -> list.append(found, [result.prototype])
    }
  })
}

/// Microseconds of scheduler busy time per message the owners handled.
fn microseconds_per_message(result: RunResult) -> Float {
  int.to_float(result.busy_microseconds)
  /. int.to_float(int.max(1, result.messages_handled))
}

fn result_of(round: List(RunResult), prototype: Prototype) -> RunResult {
  let assert Ok(result) =
    list.find(round, fn(result) { result.prototype == prototype })
    as "every round holds every prototype"
  result
}

/// What the time part found for one prototype: the median, over the paired
/// rounds, of the scheduler busy microseconds per message handled.
type Timed {
  Timed(prototype: Prototype, microseconds_per_message: Float)
}

/// The time part: `time_rounds` paired rounds of every prototype at
/// `comparison_players` players, the default visibility range and short
/// timing, on `schedulers` schedulers. Prints each prototype's median, minimum,
/// maximum and standard deviation.
fn time_per_message(schedulers schedulers: Int) -> List(Timed) {
  todo as "body in the build commit"
}

/// Rounds in which every prototype runs once at short timing, the first to run
/// rotating by one prototype from round to round so each starts about as often
/// as the others.
fn paired_rounds(
  rounds rounds: Int,
  workload workload: Workload,
  schedulers schedulers: Int,
) -> List(List(RunResult)) {
  todo as "body in the build commit"
}

/// The crash part: the microseconds from killing one owner to the rebuilt
/// owner handling a message, with no players: one creature's process for A,
/// the map process for B and for C, repeated `crash_repeats` times.
fn crash_cost(schedulers: Int) -> Nil {
  todo as "body in the build commit"
}

/// What the choosing rule reads about one prototype that kept up: its
/// 99th-percentile latency in microseconds, its scheduler busy time per
/// message and its memory per unit, at `comparison_players` players,
/// `creature_count` creatures and the default visibility range on all cores.
type Standing {
  Standing(
    prototype: Prototype,
    p99_microseconds: Int,
    microseconds_per_message: Float,
    memory_words_per_unit: Float,
  )
}

/// What decided one comparison of two prototypes.
type Decision {
  /// The 99th-percentile latencies differ by `latency_tie_microseconds` or
  /// more: the lower wins.
  LowerLatency
  /// The latencies are tied and the time per message differs by more than
  /// `resolution_percent`: the lower wins.
  LowerTimePerMessage
  /// Neither latency nor time per message separates them: the lower memory
  /// per unit wins.
  LowerMemory
}

/// One comparison of the best prototype so far with the next: who won and what
/// decided it. A tie on every measure goes to the best so far.
type Duel {
  Duel(
    best: Standing,
    challenger: Standing,
    winner: Prototype,
    decided_by: Decision,
  )
}

/// What the choosing rule ends with.
type Choice {
  /// One prototype, and the comparisons made to reach it.
  Picked(prototype: Prototype, duels: List(Duel))
  /// Every prototype is out: the cell variant must be built.
  CellVariantNeeded
}

/// The choosing rule, from the all-cores and time parts. It prints each
/// prototype's standing and the choice.
fn choose(all_cores all_cores: AllCores, timed timed: List(Timed)) -> Nil {
  todo as "body in the build commit"
}

/// The prototypes that did not fall out at the first step of the rule: those
/// that kept up at `ceiling_floor_players` players at every visibility range.
fn prototypes_left(ceilings ceilings: List(Ceiling)) -> List(Prototype) {
  todo as "body in the build commit"
}

/// The standing of one prototype that is left.
fn standing_of(
  prototype prototype: Prototype,
  all_cores all_cores: AllCores,
  timed timed: List(Timed),
) -> Standing {
  todo as "body in the build commit"
}

/// The choice among the standings of the prototypes that are left, none
/// meaning every prototype is out. Three prototypes are compared pairwise
/// against the best so far, in the order they are listed: the best so far is
/// the first, and each next one is compared with it by `duel`; the winner is
/// the best so far for the next comparison. The result can depend on the order,
/// because a tie band is not transitive.
fn pick(standings standings: List(Standing)) -> Choice {
  todo as "body in the build commit"
}

/// The rule's second and third steps for two prototypes that are left: a
/// difference in p99 latency of `latency_tie_microseconds` or more picks the
/// lower; otherwise a time per message lower by more than `resolution_percent`
/// of the other's picks the lower; otherwise the lower memory per unit picks,
/// and an equal memory per unit picks `best`.
fn duel(best best: Standing, challenger challenger: Standing) -> Duel {
  todo as "body in the build commit"
}

fn repeat(times: Int, work: fn() -> a) -> List(a) {
  int.range(0, times, [], fn(taken, _) { [work(), ..taken] })
  |> list.reverse
}

fn median(values: List(Float)) -> Float {
  let sorted = list.sort(values, float.compare)
  let count = list.length(sorted)
  let assert [_, ..] = sorted as "no values"
  case count % 2 {
    1 -> {
      let assert Ok(middle) = list.first(list.drop(sorted, count / 2))
        as "no middle"
      middle
    }
    _ -> {
      let assert [low, high, ..] = list.drop(sorted, count / 2 - 1)
        as "no middle"
      { low +. high } /. 2.0
    }
  }
}

fn minimum(values: List(Float)) -> Float {
  let assert Ok(smallest) = list.first(list.sort(values, float.compare))
    as "no values"
  smallest
}

fn maximum(values: List(Float)) -> Float {
  let assert Ok(largest) = list.last(list.sort(values, float.compare))
    as "no values"
  largest
}

fn standard_deviation(values: List(Float)) -> Float {
  let count = int.to_float(list.length(values))
  let mean = float.sum(values) /. count
  let squares =
    list.map(values, fn(value) { { value -. mean } *. { value -. mean } })
  let assert Ok(deviation) =
    float.square_root(float.sum(squares) /. { count -. 1.0 })
    as "a variance is not negative"
  deviation
}

fn two_places(value: Float) -> String {
  float.to_string(float.to_precision(value, 2))
}

fn signed(value: Float) -> String {
  case value >=. 0.0 {
    True -> "+" <> two_places(value)
    False -> two_places(value)
  }
}

fn pad_start(text: String, width: Int) -> String {
  string.pad_start(text, width, " ")
}
