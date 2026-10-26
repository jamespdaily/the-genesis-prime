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

import genesis_prime/topology/heap_limit
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/per_unit
import genesis_prime/topology/run.{type Prototype}
import genesis_prime/topology/trial.{
  type Ceiling, type Contender, type Measured, type Narrowed, type Timed,
  Contender,
}
import genesis_prime/topology/workload.{type Workload, Workload}
import gleam/dict
import gleam/erlang/reference
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/string

/// The three prototypes, in the order they are run and printed.
const prototypes = [
  run.PerUnit,
  run.MapProcess(map_process.SendsItself, heap_limit.no_limits),
  run.MapProcess(map_process.SenderPool, heap_limit.no_limits),
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

/// What the all-cores part found: the short runs of every climb, the
/// full-length confirmation runs, and each prototype's ceiling at each range.
type AllCores {
  AllCores(
    climbed: List(Measured),
    confirmed: List(Measured),
    ceilings: List(Ceiling),
  )
}

/// The prototype as a contender on `schedulers` schedulers: one map at
/// `creature_count` creatures, named as `run.name_of` prints it.
fn contender_of(
  prototype prototype: Prototype,
  schedulers schedulers: Int,
) -> Contender {
  Contender(
    name: run.name_of(prototype),
    run: fn(players, visibility_range, timing) {
      run.run(
        prototype:,
        workload: workload_for(players:, visibility_range:),
        maps: 1,
        schedulers:,
        timing:,
        sampling: run.NotSampled,
      )
    },
  )
}

/// The prototypes as contenders on `schedulers` schedulers, in the order they
/// are run and printed.
fn contenders_on(schedulers schedulers: Int) -> List(Contender) {
  list.map(prototypes, contender_of(_, schedulers))
}

/// The all-cores part: for each visibility range and prototype, the climb and
/// its confirmation. Prints the latency, ceiling and memory tables.
fn all_cores(schedulers schedulers: Int) -> AllCores {
  let climbs =
    list.flat_map(visibility_ranges, fn(visibility_range) {
      list.map(contenders_on(schedulers:), fn(contender) {
        trial.climb_and_confirm(contender:, visibility_range:, player_counts:)
      })
    })
  let suffix = ", " <> int.to_string(schedulers) <> " scheduler(s)"
  list.each(visibility_ranges, fn(visibility_range) {
    let at_range =
      list.filter(climbs, fn(found) {
        found.visibility_range == visibility_range
      })
    let short = list.flat_map(at_range, fn(found) { found.short })
    let full = list.flat_map(at_range, fn(found) { found.full })
    io.println(
      "\n== range " <> trial.two_places(visibility_range) <> " m, short runs",
    )
    trial.print_latency("prototype", suffix, short)
    trial.print_memory(suffix, short)
    io.println(
      "\n== range " <> trial.two_places(visibility_range) <> " m, full runs",
    )
    trial.print_latency("prototype", suffix, full)
    trial.print_memory(suffix, full)
  })
  let ceilings = list.map(climbs, fn(found) { found.ceiling })
  trial.print_ceiling(suffix, ceilings)
  AllCores(
    climbed: list.flat_map(climbs, fn(found) { found.short }),
    confirmed: list.flat_map(climbs, fn(found) { found.full }),
    ceilings:,
  )
}

/// The one-core part: `one_core_player_counts` for each prototype, short runs
/// on one scheduler at the default visibility range. Prints the latency table
/// with the pace of each run.
fn one_core() -> Nil {
  let visibility_range = workload.default().visibility_range
  io.println(
    "\n== one scheduler online, range "
    <> trial.two_places(visibility_range)
    <> " m, short runs",
  )
  let runs =
    list.flat_map(one_core_player_counts, fn(players) {
      list.map(contenders_on(schedulers: 1), fn(contender) {
        trial.measured_run(
          contender:,
          players:,
          visibility_range:,
          timing: run.short_timing,
        )
      })
    })
  trial.print_latency("prototype", ", 1 scheduler(s)", runs)
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
  trial.time_per_message(
    contenders: contenders_on(schedulers:),
    rounds: time_rounds,
    players: comparison_players,
    visibility_range: workload.default().visibility_range,
  )
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
        map_process.crash_cost(
          crash_workload,
          key,
          map_process.SendsItself,
          heap_limit.no_limits,
        )
      }),
    ),
    #(
      "C the map process, with senders",
      repeat(crash_repeats, fn() {
        map_process.crash_cost(
          crash_workload,
          key,
          map_process.SenderPool,
          heap_limit.no_limits,
        )
      }),
    ),
  ]
  measurement.erase_spawn_list(key)
  list.each(costs, fn(cost) {
    io.println(
      string.pad_end(cost.0, 34, " ")
      <> string.join(list.map(cost.1, int.to_string), "  ")
      <> " us, median "
      <> int.to_string(
        float.round(trial.median(list.map(cost.1, int.to_float))),
      )
      <> " us",
    )
  })
}

/// What the choosing rule ends with.
type Choice {
  /// One prototype, and what the second and third steps dropped on the way.
  Picked(prototype: String, by_latency: Narrowed, by_cpu: Narrowed)
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
    <> trial.two_places(workload.default().visibility_range)
    <> " m)",
  )
  let left = prototypes_left(ceilings: all_cores.ceilings)
  io.println(
    "1. out: did not keep up at "
    <> int.to_string(ceiling_floor_players)
    <> " players on all cores at every range",
  )
  list.each(prototypes, fn(prototype) {
    let name = run.name_of(prototype)
    let ranges =
      list.filter(all_cores.ceilings, fn(ceiling) { ceiling.contender == name })
      |> list.map(fn(ceiling) {
        trial.two_places(ceiling.visibility_range)
        <> " m: kept up at "
        <> trial.players_text(players: ceiling.kept_up_at, none: "no count")
      })
      |> string.join("; ")
    io.println(
      "   "
      <> name
      <> case list.contains(left, name) {
        True -> " stays in ("
        False -> " is out ("
      }
      <> ranges
      <> ")",
    )
  })
  let standings =
    list.filter(timed, fn(found) { list.contains(left, found.contender) })
  case pick(standings:) {
    CellVariantNeeded ->
      io.println("Every prototype is out: the cell variant must be built.")
    Picked(prototype:, by_latency:, by_cpu:) -> {
      list.each(standings, fn(standing) {
        io.println(
          "   "
          <> standing.contender
          <> ": p99 "
          <> int.to_string(standing.p99_microseconds)
          <> " us, "
          <> trial.two_places(standing.microseconds_per_message)
          <> " us/message, "
          <> trial.two_places(standing.memory_words_per_unit)
          <> " words per unit",
        )
      })
      trial.print_narrowed(
        title: "2. dropped by p99 latency (at least "
          <> int.to_string(latency_tie_microseconds)
          <> " us above the lowest)",
        narrowed: by_latency,
      )
      trial.print_narrowed(
        title: "3. dropped by time per message (more than "
          <> trial.two_places(resolution_percent)
          <> "% above the lowest)",
        narrowed: by_cpu,
      )
      io.println(
        "4. lowest memory per unit among "
        <> string.join(
          list.map(by_cpu.left, fn(standing) { standing.contender }),
          ", ",
        ),
      )
      io.println("Pick: " <> prototype)
    }
  }
}

/// The names of the prototypes that did not fall out at the first step of the
/// rule: those that kept up at `ceiling_floor_players` players at every
/// visibility range.
fn prototypes_left(ceilings ceilings: List(Ceiling)) -> List(String) {
  list.map(prototypes, run.name_of)
  |> list.filter(fn(name) {
    let own = list.filter(ceilings, fn(ceiling) { ceiling.contender == name })
    list.length(own) == list.length(visibility_ranges)
    && list.all(own, trial.keeps_up_at(_, ceiling_floor_players))
  })
}

/// The choice among the standings of the prototypes that are left, none
/// meaning every prototype is out: the rule's second, third and fourth steps.
fn pick(standings standings: List(Timed)) -> Choice {
  case standings {
    [] -> CellVariantNeeded
    [_, ..] -> {
      let by_latency =
        trial.narrow_by_latency(
          standings:,
          tie_microseconds: latency_tie_microseconds,
        )
      let by_cpu =
        trial.narrow_by_cpu(standings: by_latency.left, resolution_percent:)
      let assert [winner, ..] =
        list.sort(by_cpu.left, fn(a, b) {
          float.compare(a.memory_words_per_unit, b.memory_words_per_unit)
        })
        as "the narrowing steps always leave the lowest"
      Picked(prototype: winner.contender, by_latency:, by_cpu:)
    }
  }
}

fn repeat(times: Int, work: fn() -> a) -> List(a) {
  int.range(0, times, [], fn(taken, _) { [work(), ..taken] })
  |> list.reverse
}
