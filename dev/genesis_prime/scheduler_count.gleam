//// How many schedulers the server should run on: prototype C, a map process
//// with a sender pool, under the same load at 1, 4, 8 and all the cores'
//// worth of schedulers, in one map and in several maps at once.
////
//// Run it with `gleam run -m genesis_prime/scheduler_count` on a machine with
//// nothing else heavy running. It shares its runs and tables with
//// `genesis_prime/topology` through `genesis_prime/topology/trial`, and
//// `gleam test` never runs it. The harness process runs at high priority, and
//// the schedulers online are set back to every core at the end.
////
//// The parts, selected by naming them after `--` (none named runs all of
//// them):
////
//// - `one-map`: for each count and each visibility range in
////   `visibility_ranges`, player counts counted up with short runs until the
////   map falls behind, then the count below that and the count that fell
////   behind rerun at full length; the ceilings table.
//// - `maps`: for each count and range, one short run of `map_count` maps of
////   `players_per_map` players and `creatures_per_map` creatures each: p99,
////   max, pace, and how many maps fell behind.
//// - `time`: `time_rounds` paired short rounds across the counts at
////   `comparison_players` players, `creature_count` creatures and the default
////   range: median scheduler busy time per message, p99 and memory per unit.
//// - the choosing rule, which runs after `one-map`, `maps` and `time` when all
////   three ran.

import genesis_prime/topology/latency
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/run.{type RunResult}
import genesis_prime/topology/trial.{
  type Ceiling, type Contender, type Narrowed, type Timed, Contender,
}
import genesis_prime/topology/workload.{type Workload, Workload}
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string

/// The scheduler counts compared: 1; 4, a small service host; 8, this
/// machine's performance cores, leaving out its 4 efficiency cores; and 12,
/// every core of this machine, the BEAM's default. `counts_for` drops a count
/// above the machine's cores and adds the machine's core count when it is not
/// listed, so the last count is always every core.
const scheduler_counts = [1, 4, 8, 12]

/// The creatures on the map in the one-map and time parts.
const creature_count = 10_000

/// The player counts the one-map climb goes through, lowest first.
const player_counts = [100, 200, 400, 800]

/// The visibility ranges of the one-map and maps parts, in metres. 100 is the
/// stand-in every other run uses; 640 is the client's default draw distance
/// (`lod.viewDistance`, setting object 0x140c46410), which bounds what a
/// player can see.
const visibility_ranges = [100.0, 640.0]

/// How many maps run side by side in the maps part.
const map_count = 4

/// The players on each map of the maps part: with `map_count` maps, the same
/// 400 players as the one-map part's `ceiling_floor_players`.
const players_per_map = 100

/// The creatures on each map of the maps part: with `map_count` maps, the same
/// 10,000 creatures as `creature_count`.
const creatures_per_map = 2500

/// How many paired rounds the time per message is taken over; the median
/// counts.
const time_rounds = 5

/// The player count at which latency, time per message and memory are
/// compared by the choosing rule, at `creature_count` creatures and the
/// default visibility range.
const comparison_players = 100

/// Choosing rule, first step: a count whose map did not keep up at this many
/// players, in one map and in `map_count` maps, at every visibility range in
/// `visibility_ranges`, is out.
const ceiling_floor_players = 400

/// Choosing rule, second step: a count whose median 99th-percentile latency is
/// at least this many microseconds above the lowest left is dropped. It is a
/// tenth of the client's movement send interval, 125 ms (0x140c3a004).
const latency_tie_microseconds = 12_500

/// Choosing rule, third step: a count whose median scheduler busy time per
/// message is more than this percent above the lowest left is dropped; a
/// smaller difference is below what the harness can resolve between two runs.
const resolution_percent = 5.0

/// The parts of the run, in the order they run.
const parts = ["one-map", "maps", "time"]

/// What the maps part found for one count at one range: the short run of
/// `map_count` maps.
type ManyMaps {
  ManyMaps(schedulers: Int, visibility_range: Float, result: RunResult)
}

/// What the choosing rule ends with.
type Choice {
  /// One count, and what the second and third steps dropped on the way.
  Picked(schedulers: Int, by_latency: Narrowed, by_cpu: Narrowed)
  /// Every count is out: no count keeps up at `ceiling_floor_players` players.
  NoCountKeepsUp
}

/// Runs the parts named after `--`, or all of them, in order, and prints their
/// tables and the choosing rule's pick. The harness process runs at high
/// priority, and every core is online again at the end.
pub fn main() -> Nil {
  let chosen = case measurement.plain_arguments() {
    [] -> parts
    named -> named
  }
  list.each(chosen, fn(part) {
    assert list.contains(parts, part)
      as "a part is one of one-map, maps and time"
  })
  let runs = fn(part) { list.contains(chosen, part) }
  measurement.set_high_priority()
  measurement.enable_scheduler_wall_time()
  let cores = measurement.core_count()
  let counts = counts_for(cores:)

  let one_map_found = case runs("one-map") {
    True -> option.Some(one_map(counts:))
    False -> option.None
  }
  let many_maps_found = case runs("maps") {
    True -> option.Some(many_maps(counts:))
    False -> option.None
  }
  let timed = case runs("time") {
    True -> option.Some(time_per_message(counts:))
    False -> option.None
  }
  case one_map_found, many_maps_found, timed {
    option.Some(one_map), option.Some(many_maps), option.Some(timed) ->
      choose(counts:, one_map:, many_maps:, timed:)
    option.Some(_), option.Some(_), option.None
    | option.Some(_), option.None, _
    | option.None, _, _
    -> Nil
  }
  measurement.set_schedulers_online(cores)
}

/// The counts of `scheduler_counts` that are at most `cores`, lowest first,
/// then `cores` itself when it is not among them. This machine's performance
/// cores are 8 of its 12.
fn counts_for(cores cores: Int) -> List(Int) {
  let listed = list.filter(scheduler_counts, fn(count) { count <= cores })
  case list.contains(listed, cores) {
    True -> listed
    False -> list.append(listed, [cores])
  }
}

/// The name a count is printed under and found by in every table, such as
/// "C, 4 schedulers".
fn contender_name(schedulers schedulers: Int) -> String {
  "C, " <> int.to_string(schedulers) <> " schedulers"
}

/// The workload of one map at `players` players, `creatures` creatures and the
/// visibility range `visibility_range`.
fn workload_for(
  players players: Int,
  creatures creatures: Int,
  visibility_range visibility_range: Float,
) -> Workload {
  Workload(..workload.default(), players:, creatures:, visibility_range:)
}

/// Prototype C on `schedulers` schedulers as a contender: one map at
/// `creature_count` creatures, with the sender pool of prototype C
/// (`map_process.SenderPool`).
fn contender_of(schedulers schedulers: Int) -> Contender {
  Contender(
    name: contender_name(schedulers:),
    run: fn(players, visibility_range, timing) {
      run.run(
        prototype: run.MapProcess(map_process.SenderPool),
        workload: workload_for(
          players:,
          creatures: creature_count,
          visibility_range:,
        ),
        maps: 1,
        schedulers:,
        timing:,
      )
    },
  )
}

/// The one-map part: for each count and each range, the climb and its
/// confirmation, then the ceilings table. The ceilings, one per count and
/// range.
fn one_map(counts counts: List(Int)) -> List(Ceiling) {
  let climbs =
    list.flat_map(counts, fn(schedulers) {
      list.map(visibility_ranges, fn(visibility_range) {
        trial.climb_and_confirm(
          contender: contender_of(schedulers:),
          visibility_range:,
          player_counts:,
        )
      })
    })
  list.each(visibility_ranges, fn(visibility_range) {
    let at_range =
      list.filter(climbs, fn(found) {
        found.visibility_range == visibility_range
      })
    let suffix =
      ", one map, range " <> trial.two_places(visibility_range) <> " m"
    io.println(
      "\n== one map, range "
      <> trial.two_places(visibility_range)
      <> " m, short runs",
    )
    trial.print_latency(
      "contender",
      suffix,
      list.flat_map(at_range, fn(found) { found.short }),
    )
    io.println(
      "\n== one map, range "
      <> trial.two_places(visibility_range)
      <> " m, full runs",
    )
    trial.print_latency(
      "contender",
      suffix,
      list.flat_map(at_range, fn(found) { found.full }),
    )
  })
  let ceilings = list.map(climbs, fn(found) { found.ceiling })
  trial.print_ceiling(", one map", ceilings)
  ceilings
}

/// The maps part: for each count and each range, one short run of `map_count`
/// maps of `players_per_map` players and `creatures_per_map` creatures each,
/// then the table of `print_maps`. The runs, one per count and range.
fn many_maps(counts counts: List(Int)) -> List(ManyMaps) {
  io.println(
    "\n== maps: "
    <> int.to_string(map_count)
    <> " maps of "
    <> int.to_string(players_per_map)
    <> " players and "
    <> int.to_string(creatures_per_map)
    <> " creatures each, short runs",
  )
  let runs =
    list.flat_map(counts, fn(schedulers) {
      list.map(visibility_ranges, fn(visibility_range) {
        ManyMaps(
          schedulers:,
          visibility_range:,
          result: run.run(
            prototype: run.MapProcess(map_process.SenderPool),
            workload: workload_for(
              players: players_per_map,
              creatures: creatures_per_map,
              visibility_range:,
            ),
            maps: map_count,
            schedulers:,
            timing: run.short_timing,
          ),
        )
      })
    })
  print_maps(runs:)
  runs
}

/// Prints p99 latency, maximum latency, pace and how many maps fell behind for
/// each of `runs`.
fn print_maps(runs runs: List(ManyMaps)) -> Nil {
  io.println(
    "latency: microseconds from a move's send to its arrival at a player in range, all maps merged",
  )
  io.println(
    string.pad_end("contender", 32, " ")
    <> trial.pad_start(text: "range", width: 9)
    <> trial.pad_start(text: "players", width: 9)
    <> trial.pad_start(text: "p99", width: 10)
    <> trial.pad_start(text: "max", width: 10)
    <> "  "
    <> string.pad_end("pace", 18, " ")
    <> "maps fell behind",
  )
  list.each(runs, fn(found) {
    let fell_behind =
      list.count(found.result.map_paces, fn(pace) { pace == run.FellBehind })
    io.println(
      string.pad_end(contender_name(schedulers: found.schedulers), 32, " ")
      <> trial.pad_start(
        text: trial.two_places(found.visibility_range),
        width: 9,
      )
      <> trial.pad_start(text: int.to_string(found.result.players), width: 9)
      <> trial.pad_start(
        text: int.to_string(trial.p99_of(found.result)),
        width: 10,
      )
      <> trial.pad_start(
        text: int.to_string(latency.maximum(found.result.latency)),
        width: 10,
      )
      <> "  "
      <> string.pad_end(trial.pace_name(found.result.pace), 18, " ")
      <> int.to_string(fell_behind)
      <> " of "
      <> int.to_string(found.result.maps),
    )
  })
}

/// The time part: `time_rounds` paired rounds, rotating the starting count, of
/// every count at `comparison_players` players, `creature_count` creatures,
/// the default visibility range and short timing. Prints each run, then each
/// count's median, minimum, maximum and standard deviation of the time per
/// message and its median p99 and memory.
fn time_per_message(counts counts: List(Int)) -> List(Timed) {
  io.println(
    "\n== time: scheduler busy microseconds per message handled, "
    <> int.to_string(comparison_players)
    <> " players, "
    <> int.to_string(creature_count)
    <> " creatures, "
    <> int.to_string(time_rounds)
    <> " paired short rounds (busy time includes the players' own work)",
  )
  trial.time_per_message(
    contenders: list.map(counts, fn(schedulers) { contender_of(schedulers:) }),
    rounds: time_rounds,
    players: comparison_players,
    visibility_range: workload.default().visibility_range,
  )
}

/// The choosing rule, from the one-map, maps and time parts. It does not depend
/// on the order the counts are listed in:
///
/// 1. Out: a count whose map did not keep up at `ceiling_floor_players`
///    players in one map or in `map_count` maps, at any visibility range in
///    `visibility_ranges`. A run counts as kept up when its pace is not
///    `FellBehind`, as in the ceilings. When every count is out, it says so.
/// 2. Of those left, the lowest median 99th-percentile latency is found, and
///    every count whose latency is at least `latency_tie_microseconds` above
///    it is dropped.
/// 3. Of those left, the lowest median scheduler busy time per message is
///    found, and every count more than `resolution_percent` percent above it
///    is dropped. Of the counts within that percent, the fewest schedulers
///    wins, since it leaves cores to the database and the host.
///
/// It prints each step: who is out or dropped and why, then the pick.
fn choose(
  counts counts: List(Int),
  one_map one_map: List(Ceiling),
  many_maps many_maps: List(ManyMaps),
  timed timed: List(Timed),
) -> Nil {
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
  let left = counts_left(counts:, one_map:, many_maps:)
  io.println(
    "1. out: did not keep up at "
    <> int.to_string(ceiling_floor_players)
    <> " players in one map or in "
    <> int.to_string(map_count)
    <> " maps, at every range",
  )
  list.each(list.sort(counts, int.compare), fn(schedulers) {
    let name = contender_name(schedulers:)
    let ranges =
      list.map(visibility_ranges, fn(visibility_range) {
        let kept_up_at =
          list.find(one_map, fn(ceiling) {
            ceiling.contender == name
            && ceiling.visibility_range == visibility_range
          })
          |> result.map(fn(ceiling) { ceiling.kept_up_at })
          |> result.unwrap(option.None)
        let maps_pace =
          list.find(many_maps, fn(found) {
            found.schedulers == schedulers
            && found.visibility_range == visibility_range
          })
          |> result.map(fn(found) { trial.pace_name(found.result.pace) })
          |> result.unwrap("not run")
        trial.two_places(visibility_range)
        <> " m: one map kept up at "
        <> trial.players_text(players: kept_up_at, none: "no count")
        <> ", "
        <> int.to_string(map_count)
        <> " maps "
        <> maps_pace
      })
      |> string.join("; ")
    io.println(
      "   "
      <> name
      <> case list.contains(left, schedulers) {
        True -> " stays in ("
        False -> " is out ("
      }
      <> ranges
      <> ")",
    )
  })
  case pick(left:, timed:) {
    NoCountKeepsUp ->
      io.println(
        "Every count is out: none keeps up at "
        <> int.to_string(ceiling_floor_players)
        <> " players.",
      )
    Picked(schedulers:, by_latency:, by_cpu:) -> {
      list.each(left, fn(count) {
        let standing = standing_of(count:, timed:)
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
        "   fewest schedulers among "
        <> string.join(
          list.map(by_cpu.left, fn(standing) { standing.contender }),
          ", ",
        ),
      )
      io.println("Pick: " <> contender_name(schedulers:))
    }
  }
}

/// The counts that did not fall out at the first step of the rule, lowest
/// first.
fn counts_left(
  counts counts: List(Int),
  one_map one_map: List(Ceiling),
  many_maps many_maps: List(ManyMaps),
) -> List(Int) {
  list.sort(counts, int.compare)
  |> list.filter(fn(schedulers) {
    let name = contender_name(schedulers:)
    list.all(visibility_ranges, fn(visibility_range) {
      let one_map_keeps_up =
        list.any(one_map, fn(ceiling) {
          ceiling.contender == name
          && ceiling.visibility_range == visibility_range
          && trial.keeps_up_at(ceiling, ceiling_floor_players)
        })
      let maps_keep_up =
        list.any(many_maps, fn(found) {
          found.schedulers == schedulers
          && found.visibility_range == visibility_range
          && kept_up(found)
        })
      one_map_keeps_up && maps_keep_up
    })
  })
}

/// The standing of a count in the time part's results.
fn standing_of(count count: Int, timed timed: List(Timed)) -> Timed {
  let assert Ok(standing) =
    list.find(timed, fn(standing) {
      standing.contender == contender_name(schedulers: count)
    })
    as "the time part ran every count"
  standing
}

/// The choice among the standings of the counts that are left, lowest count
/// first: the rule's second and third steps, and the fewest schedulers among
/// the counts the third leaves. `NoCountKeepsUp` when `left` is empty.
fn pick(left left: List(Int), timed timed: List(Timed)) -> Choice {
  case list.sort(left, int.compare) {
    [] -> NoCountKeepsUp
    [_, ..] as sorted -> {
      let standings =
        list.map(sorted, fn(count) { standing_of(count:, timed:) })
      let by_latency =
        trial.narrow_by_latency(
          standings:,
          tie_microseconds: latency_tie_microseconds,
        )
      let by_cpu =
        trial.narrow_by_cpu(standings: by_latency.left, resolution_percent:)
      let assert Ok(winner) =
        list.find(sorted, fn(count) {
          list.any(by_cpu.left, fn(standing) {
            standing.contender == contender_name(schedulers: count)
          })
        })
        as "the narrowing steps always leave the lowest"
      Picked(schedulers: winner, by_latency:, by_cpu:)
    }
  }
}

/// Whether the map or maps of `found` kept up: its pace is not `FellBehind`.
fn kept_up(found: ManyMaps) -> Bool {
  found.result.pace != run.FellBehind
}
