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
//// - `time`: scheduler busy time per message, 99th-percentile latency and
////   memory per unit, in paired short rounds.
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
import gleam/result
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

/// Choosing rule, second step: a prototype whose 99th-percentile latency is at
/// least this many microseconds above the lowest left is dropped. It is a tenth
/// of the client's movement send interval, 125 ms (0x140c3a004).
const latency_tie_microseconds = 12_500

/// Choosing rule, third step: a prototype whose scheduler busy time per
/// message is more than this percent above the lowest left is dropped; a
/// smaller difference is below what the harness can resolve between two runs.
const resolution_percent = 5.0

/// How many times the crash cost of each prototype is timed.
const crash_repeats = 3

/// The parts of the run, in the order they run.
const parts = ["all-cores", "one-core", "time", "crash"]

/// Runs the parts named after `--`, or all of them, in order, and prints their
/// tables and the choosing rule's pick.
pub fn main() -> Nil {
  let chosen = case measurement.plain_arguments() {
    [] -> parts
    named -> named
  }
  list.each(chosen, fn(part) {
    assert list.contains(parts, part)
      as "a part is one of all-cores, one-core, time and crash"
  })
  let runs = fn(part) { list.contains(chosen, part) }
  measurement.set_high_priority()
  measurement.enable_scheduler_wall_time()
  let cores = measurement.core_count()

  let found = case runs("all-cores") {
    True -> option.Some(all_cores(schedulers: cores))
    False -> option.None
  }
  case runs("one-core") {
    True -> one_core()
    False -> Nil
  }
  measurement.set_schedulers_online(cores)
  let timed = case runs("time") {
    True -> option.Some(time_per_message(schedulers: cores))
    False -> option.None
  }
  case runs("crash") {
    True -> crash_cost(cores)
    False -> Nil
  }
  case found, timed {
    option.Some(found), option.Some(timed) -> choose(all_cores: found, timed:)
    option.Some(_), option.None
    | option.None, option.Some(_)
    | option.None, option.None
    -> Nil
  }
  measurement.set_schedulers_online(cores)
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

/// What one prototype's climb at one visibility range found: its short runs,
/// its full-length confirmation runs and the ceiling they show.
type Climb {
  Climb(
    visibility_range: Float,
    short: List(RunResult),
    full: List(RunResult),
    ceiling: Ceiling,
  )
}

/// The all-cores part: for each visibility range and prototype, the climb and
/// its confirmation. Prints the latency, ceiling and memory tables.
fn all_cores(schedulers schedulers: Int) -> AllCores {
  let climbs =
    list.flat_map(visibility_ranges, fn(visibility_range) {
      list.map(prototypes, fn(prototype) {
        io.println(
          "\n-- "
          <> run.name_of(prototype)
          <> ", range "
          <> two_places(visibility_range)
          <> " m: short runs, counting players up",
        )
        let short = climb(prototype:, visibility_range:, schedulers:)
        io.println("-- full-length confirmation runs")
        let full = confirm(climbed: short, visibility_range:, schedulers:)
        Climb(
          visibility_range:,
          short:,
          full:,
          ceiling: ceiling_of(prototype:, visibility_range:, confirmed: full),
        )
      })
    })
  list.each(visibility_ranges, fn(visibility_range) {
    let at_range =
      list.filter(climbs, fn(found) {
        found.visibility_range == visibility_range
      })
    let short = list.flat_map(at_range, fn(found) { found.short })
    let full = list.flat_map(at_range, fn(found) { found.full })
    io.println(
      "\n== range " <> two_places(visibility_range) <> " m, short runs",
    )
    print_latency(schedulers, short)
    print_memory(schedulers, short)
    io.println("\n== range " <> two_places(visibility_range) <> " m, full runs")
    print_latency(schedulers, full)
    print_memory(schedulers, full)
  })
  let ceilings = list.map(climbs, fn(found) { found.ceiling })
  print_ceiling(schedulers, ceilings)
  AllCores(
    climbed: list.flat_map(climbs, fn(found) { found.short }),
    confirmed: list.flat_map(climbs, fn(found) { found.full }),
    ceilings:,
  )
}

/// Short runs of one prototype at each player count of `player_counts`, lowest
/// first, stopping after the first run that fell behind; the runs, in the
/// order they ran. Owners that kept up with every count give every count's run.
fn climb(
  prototype prototype: Prototype,
  visibility_range visibility_range: Float,
  schedulers schedulers: Int,
) -> List(RunResult) {
  climb_counts(
    counts: player_counts,
    prototype:,
    visibility_range:,
    schedulers:,
    ran: [],
  )
}

fn climb_counts(
  counts counts: List(Int),
  prototype prototype: Prototype,
  visibility_range visibility_range: Float,
  schedulers schedulers: Int,
  ran ran: List(RunResult),
) -> List(RunResult) {
  case counts {
    [] -> list.reverse(ran)
    [players, ..higher] -> {
      let result =
        measured_run(
          prototype:,
          workload: workload_for(players:, visibility_range:),
          schedulers:,
          timing: run.short_timing,
        )
      case result.pace {
        run.FellBehind -> list.reverse([result, ..ran])
        run.KeptUp | run.PlayersFellBehind ->
          climb_counts(
            counts: higher,
            prototype:,
            visibility_range:,
            schedulers:,
            ran: [result, ..ran],
          )
      }
    }
  }
}

/// Full-length reruns of the highest player count of `climbed` that kept up
/// and the first that fell behind, each when there is one.
fn confirm(
  climbed climbed: List(RunResult),
  visibility_range visibility_range: Float,
  schedulers schedulers: Int,
) -> List(RunResult) {
  let highest_kept_up =
    climbed
    |> list.filter(fn(result) { result.pace != run.FellBehind })
    |> list.sort(fn(a, b) { int.compare(a.players, b.players) })
    |> list.last
  let first_fell_behind =
    climbed
    |> list.filter(fn(result) { result.pace == run.FellBehind })
    |> list.sort(fn(a, b) { int.compare(a.players, b.players) })
    |> list.first
  result.values([highest_kept_up, first_fell_behind])
  |> list.map(fn(found) {
    measured_run(
      prototype: found.prototype,
      workload: workload_for(players: found.players, visibility_range:),
      schedulers:,
      timing: run.full_timing,
    )
  })
}

/// The ceiling `confirmed`, the confirmation runs of one prototype at one
/// range, show.
fn ceiling_of(
  prototype prototype: Prototype,
  visibility_range visibility_range: Float,
  confirmed confirmed: List(RunResult),
) -> Ceiling {
  let players_where = fn(kept_up) {
    confirmed
    |> list.filter(fn(result) { { result.pace != run.FellBehind } == kept_up })
    |> list.map(fn(result) { result.players })
  }
  Ceiling(
    prototype:,
    visibility_range:,
    kept_up_at: players_where(True)
      |> list.reduce(int.max)
      |> option.from_result,
    fell_behind_at: players_where(False)
      |> list.reduce(int.min)
      |> option.from_result,
  )
}

/// Whether the prototype kept up at `players` players at the ceiling's range:
/// its highest confirmed player count that kept up reaches `players`.
fn keeps_up_at(ceiling ceiling: Ceiling, players players: Int) -> Bool {
  case ceiling.kept_up_at {
    option.Some(kept_up_at) -> kept_up_at >= players
    option.None -> False
  }
}

/// The one-core part: `one_core_player_counts` for each prototype, short runs
/// on one scheduler at the default visibility range. Prints the latency table
/// with the pace of each run.
fn one_core() -> Nil {
  let visibility_range = workload.default().visibility_range
  io.println(
    "\n== one scheduler online, range "
    <> two_places(visibility_range)
    <> " m, short runs",
  )
  let runs =
    list.flat_map(one_core_player_counts, fn(players) {
      list.map(prototypes, fn(prototype) {
        measured_run(
          prototype:,
          workload: workload_for(players:, visibility_range:),
          schedulers: 1,
          timing: run.short_timing,
        )
      })
    })
  print_latency(1, runs)
  measurement.set_schedulers_online(measurement.core_count())
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
/// for each of `runs`, with the pace of each run.
fn print_latency(schedulers: Int, runs: List(RunResult)) -> Nil {
  io.println(
    "latency: microseconds from a move's send to its arrival at a player in range, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  io.println(
    string.pad_end("prototype", 32, " ")
    <> pad_start("players", 9)
    <> pad_start("p50", 10)
    <> pad_start("p99", 10)
    <> pad_start("max", 10)
    <> pad_start("arrivals", 12)
    <> "  pace",
  )
  list.each(sorted_by_creatures_and_players(runs), fn(result) {
    io.println(
      string.pad_end(run.name_of(result.prototype), 32, " ")
      <> pad_start(int.to_string(result.players), 9)
      <> pad_start(int.to_string(latency.percentile(result.latency, 50.0)), 10)
      <> pad_start(int.to_string(latency.percentile(result.latency, 99.0)), 10)
      <> pad_start(int.to_string(latency.maximum(result.latency)), 10)
      <> pad_start(int.to_string(latency.count(result.latency)), 12)
      <> "  "
      <> pace_name(result),
    )
  })
}

/// Prints each ceiling: the highest player count that kept up and the lowest
/// that fell behind, in the full-length confirmation runs.
fn print_ceiling(schedulers: Int, ceilings: List(Ceiling)) -> Nil {
  io.println(
    "\n== ceiling: highest player count that kept up and lowest that fell behind, full-length runs only, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  list.each(ceilings, fn(ceiling) {
    io.println(
      string.pad_end(run.name_of(ceiling.prototype), 32, " ")
      <> " range "
      <> pad_start(two_places(ceiling.visibility_range), 7)
      <> " m: kept up at "
      <> players_text(ceiling.kept_up_at, "no count")
      <> ", fell behind at "
      <> players_text(ceiling.fell_behind_at, "no count"),
    )
  })
}

fn players_text(players: Option(Int), none: String) -> String {
  case players {
    option.Some(players) -> int.to_string(players) <> " players"
    option.None -> none
  }
}

/// Prints the words of memory per unit of each of `runs`.
fn print_memory(schedulers: Int, runs: List(RunResult)) -> Nil {
  io.println(
    "memory: words per unit, " <> int.to_string(schedulers) <> " scheduler(s)",
  )
  list.each(sorted_by_creatures_and_players(runs), fn(result) {
    io.println(
      string.pad_end(run.name_of(result.prototype), 32, " ")
      <> pad_start(int.to_string(result.players), 5)
      <> " players: "
      <> two_places(result.memory_words_per_unit)
      <> " words per unit",
    )
  })
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

/// Microseconds of scheduler busy time per message the owners handled.
fn microseconds_per_message(result: RunResult) -> Float {
  int.to_float(result.busy_microseconds)
  /. int.to_float(int.max(1, result.messages_handled))
}

fn p99_of(result: RunResult) -> Int {
  latency.percentile(result.latency, 99.0)
}

fn result_of(round: List(RunResult), prototype: Prototype) -> RunResult {
  let assert Ok(result) =
    list.find(round, fn(result) { result.prototype == prototype })
    as "every round holds every prototype"
  result
}

/// What the time part found for one prototype: the medians, over the paired
/// rounds, of the scheduler busy microseconds per message handled, of the
/// 99th-percentile latency in microseconds and of the memory per unit in words.
type Timed {
  Timed(
    prototype: Prototype,
    microseconds_per_message: Float,
    p99_microseconds: Int,
    memory_words_per_unit: Float,
  )
}

/// The time part: `time_rounds` paired rounds of every prototype at
/// `comparison_players` players, the default visibility range and short
/// timing, on `schedulers` schedulers. Prints each run, then each prototype's
/// median, minimum, maximum and standard deviation of the time per message and
/// the median latency and memory.
fn time_per_message(schedulers schedulers: Int) -> List(Timed) {
  io.println(
    "\n== time: scheduler busy microseconds per message handled, "
    <> int.to_string(comparison_players)
    <> " players, "
    <> int.to_string(creature_count)
    <> " creatures, "
    <> int.to_string(schedulers)
    <> " scheduler(s), "
    <> int.to_string(time_rounds)
    <> " paired short rounds (busy time includes the players' own work)",
  )
  let rounds =
    paired_rounds(
      rounds: time_rounds,
      workload: workload_for(
        players: comparison_players,
        visibility_range: workload.default().visibility_range,
      ),
      schedulers:,
    )
  list.map(prototypes, fn(prototype) {
    let results = list.map(rounds, result_of(_, prototype))
    let values = list.map(results, microseconds_per_message)
    let timed =
      Timed(
        prototype:,
        microseconds_per_message: median(values),
        p99_microseconds: float.round(
          median(list.map(results, fn(result) { int.to_float(p99_of(result)) })),
        ),
        memory_words_per_unit: median(
          list.map(results, fn(result) { result.memory_words_per_unit }),
        ),
      )
    io.println(
      string.pad_end(run.name_of(prototype), 32, " ")
      <> "median "
      <> two_places(timed.microseconds_per_message)
      <> " us/message  min "
      <> two_places(minimum(values))
      <> "  max "
      <> two_places(maximum(values))
      <> "  standard deviation "
      <> two_places(standard_deviation(values))
      <> "  median p99 "
      <> int.to_string(timed.p99_microseconds)
      <> " us  median memory "
      <> two_places(timed.memory_words_per_unit)
      <> " words per unit",
    )
    timed
  })
}

/// Rounds in which every prototype runs once at short timing, the first to run
/// rotating by one prototype from round to round so each starts about as often
/// as the others.
fn paired_rounds(
  rounds rounds: Int,
  workload workload: Workload,
  schedulers schedulers: Int,
) -> List(List(RunResult)) {
  int.range(0, rounds, [], fn(taken, round) {
    let shift = round % list.length(prototypes)
    let order =
      list.append(list.drop(prototypes, shift), list.take(prototypes, shift))
    let results =
      list.map(order, fn(prototype) {
        let result =
          measured_run(
            prototype:,
            workload:,
            schedulers:,
            timing: run.short_timing,
          )
        io.println(
          "  round "
          <> int.to_string(round + 1)
          <> " "
          <> run.name_of(prototype)
          <> ": "
          <> two_places(microseconds_per_message(result))
          <> " us/message, p99 "
          <> int.to_string(p99_of(result))
          <> " us, "
          <> int.to_string(result.messages_handled)
          <> " messages",
        )
        result
      })
    [results, ..taken]
  })
  |> list.reverse
}

/// The crash part: the microseconds from killing one owner to the rebuilt
/// owner handling a message, with no players: one creature's process for A,
/// the map process for B and for C, repeated `crash_repeats` times.
fn crash_cost(schedulers: Int) -> Nil {
  measurement.set_schedulers_online(schedulers)
  io.println(
    "\n== crash: microseconds from the owner's death to the rebuilt owner answering, "
    <> int.to_string(creature_count)
    <> " creatures, no players, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  let crash_workload =
    Workload(..workload.default(), players: 0, creatures: creature_count)
  let key = reference.new()
  measurement.put_spawn_list(
    key,
    workload.spawn_list(crash_workload)
      |> list.map(fn(unit) { #(unit.id, unit) })
      |> dict.from_list,
  )
  let costs = [
    #(
      "A one creature's process",
      repeat(crash_repeats, fn() { per_unit.crash_cost(crash_workload, key) }),
    ),
    #(
      "B the map process",
      repeat(crash_repeats, fn() {
        map_process.crash_cost(crash_workload, key, map_process.SendsItself)
      }),
    ),
    #(
      "C the map process, with senders",
      repeat(crash_repeats, fn() {
        map_process.crash_cost(crash_workload, key, map_process.SenderPool)
      }),
    ),
  ]
  measurement.erase_spawn_list(key)
  list.each(costs, fn(cost) {
    io.println(
      string.pad_end(cost.0, 34, " ")
      <> string.join(list.map(cost.1, int.to_string), "  ")
      <> " us, median "
      <> int.to_string(float.round(median(list.map(cost.1, int.to_float))))
      <> " us",
    )
  })
}

/// What the choosing rule reads about one prototype that kept up: its
/// 99th-percentile latency in microseconds, its scheduler busy time per
/// message and its memory per unit, each the median of the time part's paired
/// rounds at `comparison_players` players, `creature_count` creatures and the
/// default visibility range on all cores.
type Standing {
  Standing(
    prototype: Prototype,
    p99_microseconds: Int,
    microseconds_per_message: Float,
    memory_words_per_unit: Float,
  )
}

/// A prototype dropped at one step of the choosing rule, and why.
type Dropped {
  Dropped(prototype: Prototype, reason: String)
}

/// What one step of the choosing rule left and dropped.
type Narrowed {
  Narrowed(left: List(Standing), dropped: List(Dropped))
}

/// What the choosing rule ends with.
type Choice {
  /// One prototype, and what the second and third steps dropped on the way.
  Picked(prototype: Prototype, by_latency: Narrowed, by_cpu: Narrowed)
  /// Every prototype is out: the cell variant must be built.
  CellVariantNeeded
}

/// The choosing rule, from the all-cores and time parts. It does not depend on
/// the order the prototypes are listed in:
///
/// 1. Out: a prototype that did not keep up at `ceiling_floor_players` players
///    on all cores at every range in `visibility_ranges`. When every
///    prototype is out, the cell variant must be built.
/// 2. Of those left, the lowest 99th-percentile latency is found, and every
///    prototype whose latency is at least `latency_tie_microseconds` above it
///    is dropped.
/// 3. Of those left, the lowest scheduler busy time per message is found, and
///    every prototype more than `resolution_percent` percent above it is
///    dropped.
/// 4. Of those left, the lowest memory per unit wins.
///
/// The latency, time per message and memory are the medians of the time part's
/// paired rounds. It prints each step: who is out or dropped and why, then the
/// pick.
fn choose(all_cores all_cores: AllCores, timed timed: List(Timed)) -> Nil {
  io.println(
    "\n== The choosing rule (latency, time per message and memory are medians of "
    <> int.to_string(time_rounds)
    <> " paired short rounds at "
    <> int.to_string(comparison_players)
    <> " players, "
    <> int.to_string(creature_count)
    <> " creatures, "
    <> two_places(workload.default().visibility_range)
    <> " m)",
  )
  let left = prototypes_left(ceilings: all_cores.ceilings)
  io.println(
    "1. out: did not keep up at "
    <> int.to_string(ceiling_floor_players)
    <> " players on all cores at every range",
  )
  list.each(prototypes, fn(prototype) {
    let ranges =
      list.filter(all_cores.ceilings, fn(ceiling) {
        ceiling.prototype == prototype
      })
      |> list.map(fn(ceiling) {
        two_places(ceiling.visibility_range)
        <> " m: kept up at "
        <> players_text(ceiling.kept_up_at, "no count")
      })
      |> string.join("; ")
    io.println(
      "   "
      <> run.name_of(prototype)
      <> case list.contains(left, prototype) {
        True -> " stays in ("
        False -> " is out ("
      }
      <> ranges
      <> ")",
    )
  })
  let standings = list.map(left, standing_of(_, timed))
  case pick(standings:) {
    CellVariantNeeded ->
      io.println("Every prototype is out: the cell variant must be built.")
    Picked(prototype:, by_latency:, by_cpu:) -> {
      list.each(standings, fn(standing) {
        io.println(
          "   "
          <> run.name_of(standing.prototype)
          <> ": p99 "
          <> int.to_string(standing.p99_microseconds)
          <> " us, "
          <> two_places(standing.microseconds_per_message)
          <> " us/message, "
          <> two_places(standing.memory_words_per_unit)
          <> " words per unit",
        )
      })
      print_narrowed(
        "2. dropped by p99 latency (at least "
          <> int.to_string(latency_tie_microseconds)
          <> " us above the lowest)",
        by_latency,
      )
      print_narrowed(
        "3. dropped by time per message (more than "
          <> two_places(resolution_percent)
          <> "% above the lowest)",
        by_cpu,
      )
      io.println(
        "4. lowest memory per unit among "
        <> string.join(
          list.map(by_cpu.left, fn(standing) { run.name_of(standing.prototype) }),
          ", ",
        ),
      )
      io.println("Pick: " <> run.name_of(prototype))
    }
  }
}

fn print_narrowed(title: String, narrowed: Narrowed) -> Nil {
  io.println(title)
  case narrowed.dropped {
    [] -> io.println("   none dropped")
    dropped ->
      list.each(dropped, fn(found) {
        io.println(
          "   " <> run.name_of(found.prototype) <> ": " <> found.reason,
        )
      })
  }
}

/// The prototypes that did not fall out at the first step of the rule: those
/// that kept up at `ceiling_floor_players` players at every visibility range.
fn prototypes_left(ceilings ceilings: List(Ceiling)) -> List(Prototype) {
  list.filter(prototypes, fn(prototype) {
    let own =
      list.filter(ceilings, fn(ceiling) { ceiling.prototype == prototype })
    list.length(own) == list.length(visibility_ranges)
    && list.all(own, keeps_up_at(_, ceiling_floor_players))
  })
}

/// The standing of one prototype that is left.
fn standing_of(
  prototype prototype: Prototype,
  timed timed: List(Timed),
) -> Standing {
  let assert Ok(found) =
    list.find(timed, fn(found) { found.prototype == prototype })
    as "the time part holds every prototype"
  Standing(
    prototype:,
    p99_microseconds: found.p99_microseconds,
    microseconds_per_message: found.microseconds_per_message,
    memory_words_per_unit: found.memory_words_per_unit,
  )
}

/// The choice among the standings of the prototypes that are left, none
/// meaning every prototype is out: the rule's second, third and fourth steps.
fn pick(standings standings: List(Standing)) -> Choice {
  case standings {
    [] -> CellVariantNeeded
    [_, ..] -> {
      let by_latency =
        narrow(
          standings:,
          measure: fn(standing) { int.to_float(standing.p99_microseconds) },
          too_far: fn(value, lowest) {
            value -. lowest >=. int.to_float(latency_tie_microseconds)
          },
          reason: fn(standing, lowest) {
            "p99 "
            <> int.to_string(standing.p99_microseconds)
            <> " us is "
            <> two_places(int.to_float(standing.p99_microseconds) -. lowest)
            <> " us above the lowest, "
            <> two_places(lowest)
            <> " us"
          },
        )
      let by_cpu =
        narrow(
          standings: by_latency.left,
          measure: fn(standing) { standing.microseconds_per_message },
          too_far: fn(value, lowest) {
            percent_above(value, lowest) >. resolution_percent
          },
          reason: fn(standing, lowest) {
            two_places(standing.microseconds_per_message)
            <> " us/message is "
            <> signed(percent_above(standing.microseconds_per_message, lowest))
            <> "% above the lowest, "
            <> two_places(lowest)
            <> " us/message"
          },
        )
      let assert [winner, ..] =
        list.sort(by_cpu.left, fn(a, b) {
          float.compare(a.memory_words_per_unit, b.memory_words_per_unit)
        })
        as "the narrowing steps always leave the lowest"
      Picked(prototype: winner.prototype, by_latency:, by_cpu:)
    }
  }
}

/// The standings whose `measure` is not too far above the lowest `measure`
/// among them, in their order, and the others with why they were dropped.
fn narrow(
  standings standings: List(Standing),
  measure measure: fn(Standing) -> Float,
  too_far too_far: fn(Float, Float) -> Bool,
  reason reason: fn(Standing, Float) -> String,
) -> Narrowed {
  let assert Ok(lowest) = list.reduce(list.map(standings, measure), float.min)
    as "a step is given at least one standing"
  let #(left, far) =
    list.partition(standings, fn(standing) {
      !too_far(measure(standing), lowest)
    })
  Narrowed(
    left:,
    dropped: list.map(far, fn(standing) {
      Dropped(prototype: standing.prototype, reason: reason(standing, lowest))
    }),
  )
}

/// How many percent of `lowest` the `value` is above it.
fn percent_above(value: Float, lowest: Float) -> Float {
  { value -. lowest } /. lowest *. 100.0
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
