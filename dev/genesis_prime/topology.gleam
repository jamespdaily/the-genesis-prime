//// Which process owns a unit's state: one process per unit with its position
//// in a shared table, or one process that owns the whole map. The two
//// prototypes run the same game rules under the same load, and only the
//// ownership differs.
////
//// Run it with `gleam run -m genesis_prime/topology` on a machine with
//// nothing else heavy running. It lives in `dev/` because Gleam compiles that
//// directory with the project, so `gleam build` keeps it compiling, while
//// `gleam test` never runs it. It uses only the runtime's own counters, so it
//// can be run again on the real map.
////
//// It runs the measures in order and prints a table for each, then the
//// prototype the choosing rule picks. Measure 1, that both prototypes are
//// correct, is the test suite: `gleam test` must pass before these numbers
//// count. Measures 2 to 5 run on all the cores and then on each count in
//// `scheduler_counts`; the planted cost, the visibility sweep and the crash
//// cost run on all the cores.

import genesis_prime/topology/latency
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/per_unit
import genesis_prime/topology/run.{type Prototype, type RunResult}
import genesis_prime/topology/workload.{type Workload, Workload}
import gleam/dict
import gleam/erlang/reference
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/order
import gleam/string

/// The player counts a run uses.
const player_counts = [100, 200, 400, 800]

/// The creature counts a run uses.
const creature_counts = [1000, 10_000]

/// The scheduler counts of the scheduler measure, besides all the cores.
const scheduler_counts = [1]

/// How many runs the time per message is taken over; the median counts.
const time_runs = 5

/// How many rounds the planted-cost measure pairs.
const planted_rounds = 5

/// The player count at which the choosing rule compares latency.
const comparison_players = 100

/// The creature count at which time per message and the planted cost are
/// measured.
const comparison_creatures = 10_000

/// Choosing rule, first step: a prototype whose ceiling, on all cores, is
/// below this many players in one map is out.
const ceiling_floor_players = 400

/// Choosing rule, second step: prototypes whose 99th-percentile latency at
/// `comparison_players` is within this percent of each other are tied, and the
/// one with less memory per unit wins.
const latency_tie_percent = 10.0

/// The visibility ranges of the sweep, in metres. The first is the stand-in
/// every other run uses; 256 and 640 are the client's minimum and default draw
/// distance (`lod.viewDistance`, setting object 0x140c46410), which bound what
/// a player can see.
const visibility_ranges = [100.0, 256.0, 640.0]

/// How many times the crash cost of each prototype is timed.
const crash_repeats = 3

/// Runs measures 2 to 6 in order and prints their tables and the choosing
/// rule's pick.
pub fn main() -> Nil {
  io.println(
    "== Measure 1: correctness is the test suite; `gleam test` must pass before these numbers count",
  )
  measurement.enable_scheduler_wall_time()
  let cores = measurement.core_count()
  let prototypes = [run.PerUnit, run.MapProcess(map_process.NoPlantedCost)]
  let default_range = workload.default().visibility_range

  let all_cores_runs =
    measures_2_to_5(
      schedulers: cores,
      prototypes:,
      visibility_range: default_range,
    )
  list.each(scheduler_counts, fn(count) {
    measures_2_to_5(
      schedulers: count,
      prototypes:,
      visibility_range: default_range,
    )
    Nil
  })

  measurement.set_schedulers_online(cores)
  planted_cost(cores)
  let sweep =
    visibility_sweep(schedulers: cores, prototypes:, grid: all_cores_runs)
  print_sweep(sweep)
  crash_cost(cores)
  choose(prototypes, all_cores_runs)
  measurement.set_schedulers_online(cores)
}

/// Runs the grid of player and creature counts for both prototypes with
/// `schedulers` schedulers online, the paired time runs, and prints
/// measures 2 to 5. Returns the grid's runs.
fn measures_2_to_5(
  schedulers schedulers: Int,
  prototypes prototypes: List(Prototype),
  visibility_range visibility_range: Float,
) -> List(RunResult) {
  io.println(
    "\n== "
    <> int.to_string(schedulers)
    <> " scheduler(s) online: raw runs, one per prototype, player count and creature count",
  )
  let runs =
    list.flat_map(creature_counts, fn(creatures) {
      list.flat_map(player_counts, fn(players) {
        list.map(prototypes, fn(prototype) {
          measured_run(
            prototype:,
            workload: workload_for(players:, creatures:, visibility_range:),
            schedulers:,
          )
        })
      })
    })
  print_latency(schedulers, runs)
  print_ceiling(schedulers, runs)
  print_memory(schedulers, runs)
  time_per_message(schedulers, prototypes)
  runs
}

fn workload_for(
  players players: Int,
  creatures creatures: Int,
  visibility_range visibility_range: Float,
) -> Workload {
  Workload(..workload.default(), players:, creatures:, visibility_range:)
}

/// One run with the full timing, printed as it finishes.
fn measured_run(
  prototype prototype: Prototype,
  workload workload: Workload,
  schedulers schedulers: Int,
) -> RunResult {
  let result = run.run(prototype, workload, schedulers, run.full_timing)
  io.println(
    string.pad_end(run.name_of(prototype), 24, " ")
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

fn pace_name(result: RunResult) -> String {
  case result.pace {
    run.KeptUp -> "KeptUp"
    run.FellBehind -> "FellBehind"
  }
}

fn print_latency(schedulers: Int, runs: List(RunResult)) -> Nil {
  io.println(
    "\n== Measure 3: microseconds from a move's send to its arrival at a player in range, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  io.println(
    string.pad_end("prototype", 24, " ")
    <> pad_start("creatures", 10)
    <> pad_start("players", 9)
    <> pad_start("p50", 10)
    <> pad_start("p99", 10)
    <> pad_start("max", 10)
    <> pad_start("arrivals", 12),
  )
  list.each(sorted_by_creatures_and_players(runs), fn(result) {
    io.println(
      string.pad_end(run.name_of(result.prototype), 24, " ")
      <> pad_start(int.to_string(result.creatures), 10)
      <> pad_start(int.to_string(result.players), 9)
      <> pad_start(int.to_string(latency.percentile(result.latency, 50.0)), 10)
      <> pad_start(int.to_string(latency.percentile(result.latency, 99.0)), 10)
      <> pad_start(int.to_string(latency.maximum(result.latency)), 10)
      <> pad_start(int.to_string(latency.count(result.latency)), 12),
    )
  })
}

fn print_ceiling(schedulers: Int, runs: List(RunResult)) -> Nil {
  io.println(
    "\n== Measure 4: lowest player count at which an owner's queue grew (FellBehind), "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  list.each(creature_counts, fn(creatures) {
    list.each(prototypes_in(runs), fn(prototype) {
      let ceiling =
        runs
        |> list.filter(fn(result) {
          result.prototype == prototype
          && result.creatures == creatures
          && result.pace == run.FellBehind
        })
        |> list.map(fn(result) { result.players })
        |> list.sort(int.compare)
        |> list.first
      io.println(
        string.pad_end(run.name_of(prototype), 24, " ")
        <> pad_start(int.to_string(creatures), 7)
        <> " creatures: "
        <> case ceiling {
          Ok(players) ->
            "fell behind at " <> int.to_string(players) <> " players"
          Error(Nil) -> "kept up at every count tried"
        },
      )
    })
  })
}

fn print_memory(schedulers: Int, runs: List(RunResult)) -> Nil {
  io.println(
    "\n== Measure 5: words of memory per unit, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  list.each(sorted_by_creatures_and_players(runs), fn(result) {
    io.println(
      string.pad_end(run.name_of(result.prototype), 24, " ")
      <> pad_start(int.to_string(result.creatures), 7)
      <> " creatures "
      <> pad_start(int.to_string(result.players), 4)
      <> " players: "
      <> two_places(result.memory_words_per_unit)
      <> " words per unit",
    )
  })
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

/// Measure 2: runs each prototype `time_runs` times at the comparison counts,
/// in rounds that alternate which one starts, and prints the median.
fn time_per_message(schedulers: Int, prototypes: List(Prototype)) -> Nil {
  io.println(
    "\n== Measure 2: scheduler busy microseconds per message handled, "
    <> int.to_string(comparison_players)
    <> " players, "
    <> int.to_string(comparison_creatures)
    <> " creatures, "
    <> int.to_string(schedulers)
    <> " scheduler(s), "
    <> int.to_string(time_runs)
    <> " paired rounds (busy time includes the players' own work)",
  )
  let rounds =
    paired_rounds(
      prototypes:,
      rounds: time_runs,
      workload: workload_for(
        players: comparison_players,
        creatures: comparison_creatures,
        visibility_range: workload.default().visibility_range,
      ),
      schedulers:,
    )
  list.each(prototypes, fn(prototype) {
    let values =
      list.map(rounds, fn(round) {
        microseconds_per_message(result_of(round, prototype))
      })
    io.println(
      string.pad_end(run.name_of(prototype), 24, " ")
      <> "median "
      <> two_places(median(values))
      <> " us/message  min "
      <> two_places(minimum(values))
      <> "  max "
      <> two_places(maximum(values))
      <> "  standard deviation "
      <> two_places(standard_deviation(values)),
    )
  })
}

fn result_of(round: List(RunResult), prototype: Prototype) -> RunResult {
  let assert Ok(result) =
    list.find(round, fn(result) { result.prototype == prototype })
    as "every round holds every prototype"
  result
}

/// Rounds in which every prototype runs once, the first to run alternating
/// from round to round.
fn paired_rounds(
  prototypes prototypes: List(Prototype),
  rounds rounds: Int,
  workload workload: Workload,
  schedulers schedulers: Int,
) -> List(List(RunResult)) {
  int.range(0, rounds, [], fn(taken, round) {
    let order = case round % 2 {
      0 -> prototypes
      _ -> list.reverse(prototypes)
    }
    let results =
      list.map(order, fn(prototype) {
        let result = measured_run(prototype:, workload:, schedulers:)
        io.println(
          "  round "
          <> int.to_string(round + 1)
          <> ": "
          <> two_places(microseconds_per_message(result))
          <> " us/message, "
          <> int.to_string(result.messages_handled)
          <> " messages",
        )
        result
      })
    [results, ..taken]
  })
  |> list.reverse
}

/// Measure 8: the map process against the same with a planted extra grid
/// lookup on every move, in paired rounds, on all the cores.
fn planted_cost(schedulers: Int) -> Nil {
  io.println(
    "\n== Measure 8: the planted extra grid lookup per move, "
    <> int.to_string(planted_rounds)
    <> " paired rounds, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  let plain = run.MapProcess(map_process.NoPlantedCost)
  let planted = run.MapProcess(map_process.ExtraGridLookupPerMove)
  let rounds =
    paired_rounds(
      prototypes: [plain, planted],
      rounds: planted_rounds,
      workload: workload_for(
        players: comparison_players,
        creatures: comparison_creatures,
        visibility_range: workload.default().visibility_range,
      ),
      schedulers:,
    )
  let plain_values =
    list.map(rounds, fn(round) {
      microseconds_per_message(result_of(round, plain))
    })
  let planted_values =
    list.map(rounds, fn(round) {
      microseconds_per_message(result_of(round, planted))
    })
  let difference = median(planted_values) -. median(plain_values)
  let ratios =
    list.map2(plain_values, planted_values, fn(plain, planted) {
      planted /. plain
    })
  io.println(
    "median planted - median plain: "
    <> two_places(difference)
    <> " us/message; range of plain's runs: "
    <> two_places(maximum(plain_values) -. minimum(plain_values))
    <> "; the harness "
    <> case difference >. maximum(plain_values) -. minimum(plain_values) {
      True -> "sees the difference"
      False -> "does not see the difference"
    },
  )
  io.println(
    "per-round planted/plain: median "
    <> signed({ median(ratios) -. 1.0 } *. 100.0)
    <> "%, planted slower in "
    <> int.to_string(list.count(ratios, fn(ratio) { ratio >. 1.0 }))
    <> " of "
    <> int.to_string(planted_rounds)
    <> " rounds",
  )
}

/// A run of the visibility sweep.
type Swept {
  Swept(visibility_range: Float, result: RunResult)
}

/// Runs both prototypes at the comparison creature count for every visibility
/// range and player count. The runs at the default range are the grid's.
fn visibility_sweep(
  schedulers schedulers: Int,
  prototypes prototypes: List(Prototype),
  grid grid: List(RunResult),
) -> List(Swept) {
  io.println(
    "\n== Visibility sweep: "
    <> int.to_string(comparison_creatures)
    <> " creatures, "
    <> int.to_string(schedulers)
    <> " scheduler(s), raw runs",
  )
  list.flat_map(visibility_ranges, fn(visibility_range) {
    list.flat_map(prototypes, fn(prototype) {
      list.map(player_counts, fn(players) {
        Swept(
          visibility_range:,
          result: swept_run(
            prototype:,
            players:,
            visibility_range:,
            schedulers:,
            grid:,
          ),
        )
      })
    })
  })
}

/// One run of the sweep: the grid's own run when the range is the default
/// one, else a new run.
fn swept_run(
  prototype prototype: Prototype,
  players players: Int,
  visibility_range visibility_range: Float,
  schedulers schedulers: Int,
  grid grid: List(RunResult),
) -> RunResult {
  case visibility_range == workload.default().visibility_range {
    True -> {
      let assert Ok(result) =
        list.find(grid, fn(result) {
          result.prototype == prototype
          && result.players == players
          && result.creatures == comparison_creatures
        })
        as "the grid holds every default-range run"
      result
    }
    False ->
      measured_run(
        prototype:,
        workload: workload_for(
          players:,
          creatures: comparison_creatures,
          visibility_range:,
        ),
        schedulers:,
      )
  }
}

fn print_sweep(sweep: List(Swept)) -> Nil {
  io.println(
    "\n== Visibility sweep: microseconds from a move's send to its arrival, and pace",
  )
  io.println(
    string.pad_end("prototype", 24, " ")
    <> pad_start("range", 9)
    <> pad_start("players", 9)
    <> pad_start("p50", 10)
    <> pad_start("p99", 10)
    <> pad_start("max", 10)
    <> "  pace",
  )
  list.each(sweep, fn(swept) {
    let result = swept.result
    io.println(
      string.pad_end(run.name_of(result.prototype), 24, " ")
      <> pad_start(two_places(swept.visibility_range), 9)
      <> pad_start(int.to_string(result.players), 9)
      <> pad_start(int.to_string(latency.percentile(result.latency, 50.0)), 10)
      <> pad_start(int.to_string(latency.percentile(result.latency, 99.0)), 10)
      <> pad_start(int.to_string(latency.maximum(result.latency)), 10)
      <> "  "
      <> pace_name(result),
    )
  })
}

/// Measure 6: the microseconds from killing one owner to the rebuilt process
/// handling a message: one creature's process for A, the whole map process
/// for B, at the comparison creature count and no players.
fn crash_cost(schedulers: Int) -> Nil {
  io.println(
    "\n== Measure 6: microseconds from the owner's death to the rebuilt owner answering, "
    <> int.to_string(comparison_creatures)
    <> " creatures, no players, "
    <> int.to_string(schedulers)
    <> " scheduler(s)",
  )
  let crash_workload =
    Workload(..workload.default(), players: 0, creatures: comparison_creatures)
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
        map_process.crash_cost(crash_workload, key, map_process.NoPlantedCost)
      }),
    ),
  ]
  measurement.erase_spawn_list(key)
  list.each(costs, fn(cost) {
    io.println(
      string.pad_end(cost.0, 28, " ")
      <> string.join(list.map(cost.1, int.to_string), "  ")
      <> " us, median "
      <> int.to_string(float.round(median(list.map(cost.1, int.to_float))))
      <> " us",
    )
  })
}

fn repeat(times: Int, work: fn() -> a) -> List(a) {
  int.range(0, times, [], fn(taken, _) { [work(), ..taken] })
  |> list.reverse
}

/// The choosing rule: a prototype that fell behind below
/// `ceiling_floor_players` players on all the cores is out; of those left the
/// one with the lower 99th-percentile latency at the comparison counts wins,
/// and within `latency_tie_percent` the one with less memory per unit; when
/// both are out the cell variant is built.
fn choose(prototypes: List(Prototype), all_cores_runs: List(RunResult)) -> Nil {
  io.println("\n== The choosing rule, from the runs on all the cores")
  let out = fn(prototype) {
    list.any(all_cores_runs, fn(result) {
      result.prototype == prototype
      && result.players < ceiling_floor_players
      && result.pace == run.FellBehind
    })
  }
  list.each(prototypes, fn(prototype) {
    io.println(
      run.name_of(prototype)
      <> case out(prototype) {
        True ->
          " is out: it fell behind below "
          <> int.to_string(ceiling_floor_players)
          <> " players"
        False ->
          " is in: it kept up below "
          <> int.to_string(ceiling_floor_players)
          <> " players"
      },
    )
  })
  case list.filter(prototypes, fn(prototype) { !out(prototype) }) {
    [] ->
      io.println(
        "Both prototypes are out: the cell variant must be built, and measures 1 to 5 rerun on it.",
      )
    [only] ->
      io.println("Pick: " <> run.name_of(only) <> ", the only one left.")
    left -> {
      let compared =
        list.map(left, fn(prototype) {
          let assert Ok(result) =
            list.find(all_cores_runs, fn(result) {
              result.prototype == prototype
              && result.players == comparison_players
              && result.creatures == comparison_creatures
            })
            as "the grid holds the comparison run"
          #(
            prototype,
            int.to_float(latency.percentile(result.latency, 99.0)),
            result.memory_words_per_unit,
          )
        })
      let assert [first, second, ..] = compared as "two prototypes are left"
      let lower_latency = case first.1 <=. second.1 {
        True -> #(first, second)
        False -> #(second, first)
      }
      let #(faster, slower) = lower_latency
      let tied = within_percent(faster.1, slower.1)
      let picked = case tied && slower.2 <. faster.2 {
        True -> slower
        False -> faster
      }
      io.println(
        "p99 at "
        <> int.to_string(comparison_players)
        <> " players and "
        <> int.to_string(comparison_creatures)
        <> " creatures: "
        <> run.name_of(first.0)
        <> " "
        <> two_places(first.1)
        <> " us, "
        <> run.name_of(second.0)
        <> " "
        <> two_places(second.1)
        <> " us; "
        <> case tied {
          True ->
            "within "
            <> two_places(latency_tie_percent)
            <> "% of each other, so memory per unit decides: "
          False ->
            "not within "
            <> two_places(latency_tie_percent)
            <> "%, so latency decides: "
        }
        <> run.name_of(first.0)
        <> " "
        <> two_places(first.2)
        <> " words, "
        <> run.name_of(second.0)
        <> " "
        <> two_places(second.2)
        <> " words",
      )
      io.println("Pick: " <> run.name_of(picked.0))
    }
  }
}

/// Whether two latencies are within `latency_tie_percent` of each other,
/// measured against the lower.
fn within_percent(a: Float, b: Float) -> Bool {
  let lower = float.min(a, b)
  let higher = float.max(a, b)
  higher -. lower <=. lower *. latency_tie_percent /. 100.0
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
