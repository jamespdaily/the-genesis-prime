//// One load run: a prototype and its players started together, a warm-up,
//// a measured stretch, and what the run counted.

import genesis_prime/topology/latency.{type Histogram}
import genesis_prime/topology/map_process.{type PlantedCost}
import genesis_prime/topology/measurement
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/per_unit
import genesis_prime/topology/player
import genesis_prime/topology/unit
import genesis_prime/topology/workload.{type Workload}
import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result

/// How long each stretch of a run lasts, in milliseconds.
pub type Timing {
  Timing(
    /// How long the load runs before anything is counted.
    warm_up_milliseconds: Int,
    /// How long the measured stretch lasts.
    measure_milliseconds: Int,
    /// How often the owners' queues are sampled during the measured stretch.
    sample_interval_milliseconds: Int,
  )
}

/// The timing of a full run: 5 seconds of warm-up, a measured stretch of 30
/// seconds and a sample every second.
pub const full_timing =
  Timing(
    warm_up_milliseconds: 5000,
    measure_milliseconds: 30_000,
    sample_interval_milliseconds: 1000,
  )

/// The first sample, counted from the start of the measured stretch, that
/// counts toward falling behind.
const first_judged_sample = 10

/// Which prototype a run measures.
pub type Prototype {
  /// One process per unit.
  PerUnit
  /// One map process, with a planted cost or none.
  MapProcess(planted: PlantedCost)
}

/// Whether the owners kept up with the load.
pub type Pace {
  /// No judged sample's queue exceeded what the load sends in one second.
  KeptUp
  /// A judged sample's queue exceeded what the load sends in one second.
  FellBehind
  /// The owners kept up, but a player did not report within
  /// `report_deadline_milliseconds`: the updates sent to it outran it. The
  /// choosing rule's ceiling reads only the owners, so this counts as kept up
  /// there, and its latency covers only the players that reported.
  PlayersFellBehind
}

/// How long the players together have to report after the measured stretch.
const report_deadline_milliseconds = 30_000

/// What one run counted over its measured stretch.
pub type RunResult {
  RunResult(
    prototype: Prototype,
    players: Int,
    creatures: Int,
    schedulers: Int,
    moves_sent: Int,
    updates_received: Int,
    busy_microseconds: Int,
    messages_handled: Int,
    latency: Histogram,
    queue_samples: List(Int),
    memory_words_per_unit: Float,
    pace: Pace,
  )
}

/// The messages the load sends to the owners in one second: every player's
/// moves and attack, and every creature's think.
fn load_per_second(workload: Workload) -> Int {
  workload.players * { workload.moves_per_second + 1 } + workload.creatures
}

/// Whether the owners kept up: from `first_judged_sample` on, no sample of the
/// owners' summed queue may exceed `load_per_second`.
fn pace(
  queue_samples queue_samples: List(Int),
  load_per_second load_per_second: Int,
) -> Pace {
  let judged = list.drop(queue_samples, first_judged_sample - 1)
  case list.any(judged, fn(queue) { queue > load_per_second }) {
    True -> FellBehind
    False -> KeptUp
  }
}

/// The name of a prototype as it is printed in a table.
pub fn name_of(prototype: Prototype) -> String {
  case prototype {
    PerUnit -> "A one process per unit"
    MapProcess(planted: map_process.NoPlantedCost) -> "B one map process"
    MapProcess(planted: map_process.ExtraGridLookupPerMove) ->
      "B planted extra lookup"
  }
}

/// Runs the load once, with `schedulers` schedulers online: starts one
/// supervisor with the prototype first and the players' factory after it,
/// tells each player to begin, which joins its connection, runs
/// the warm-up, counts through the measured stretch while sampling the
/// owners' summed queue each interval, and stops everything. The spawn list is
/// kept under a key made for the run and erased at the end.
pub fn run(
  prototype prototype: Prototype,
  workload workload: Workload,
  schedulers schedulers: Int,
  timing timing: Timing,
) -> RunResult {
  measurement.set_schedulers_online(schedulers)
  let spawn_list = workload.spawn_list(workload)
  let key = reference.new()
  measurement.put_spawn_list(
    key,
    dict.from_list(list.map(spawn_list, fn(unit) { #(unit.id, unit) })),
  )
  let door_ready = process.new_subject()
  let factory_ready = process.new_subject()
  let prototype_child =
    supervision.supervisor(fn() { start_prototype(prototype:, workload:, key:) })
    |> owner.reporting(door_ready)
  let players_child =
    player.factory(workload)
    |> factory_supervisor.supervised
    |> owner.reporting(factory_ready)
  let assert Ok(supervisor) =
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.add(prototype_child)
    |> static_supervisor.add(players_child)
    |> static_supervisor.start
    as "the run's supervisor did not start"
  let assert Ok(door) = process.receive(door_ready, 5000)
    as "the prototype did not report its owner"
  let assert Ok(factory) = process.receive(factory_ready, 5000)
    as "the players' supervisor did not report itself"
  let players =
    spawn_list
    |> list.filter(fn(unit) { unit.kind == unit.Player })
    |> list.map(fn(unit) {
      let assert Ok(started) = factory_supervisor.start_child(factory, unit)
        as "a player did not start"
      started.data
    })
  list.each(players, player.begin(_, door))
  process.sleep(timing.warm_up_milliseconds)

  list.each(players, player.reset_counts)
  let handled_before = door.messages_handled()
  let scheduler_before = measurement.scheduler_time()
  let queue_samples = sample_queues(door, timing)
  let scheduler_after = measurement.scheduler_time()
  let handled_after = door.messages_handled()
  let memory_words = door.memory_words()
  let asked = list.map(players, player.ask_report)
  let deadline =
    measurement.monotonic_microseconds() / 1000 + report_deadline_milliseconds
  let answers =
    list.map(asked, fn(reply) {
      let left = deadline - measurement.monotonic_microseconds() / 1000
      process.receive(reply, int.max(left, 0))
    })
  let reports = result.values(answers)
  let owners_pace =
    pace(queue_samples:, load_per_second: load_per_second(workload))
  owner.stop_supervisor(supervisor.pid)
  measurement.erase_spawn_list(key)

  RunResult(
    prototype:,
    players: workload.players,
    creatures: workload.creatures,
    schedulers:,
    moves_sent: int.sum(list.map(reports, fn(report) { report.moves_sent })),
    updates_received: int.sum(
      list.map(reports, fn(report) { report.updates_received }),
    ),
    busy_microseconds: scheduler_after.busy_microseconds
      - scheduler_before.busy_microseconds,
    messages_handled: handled_after - handled_before,
    latency: list.fold(reports, latency.new(), fn(merged, report) {
      latency.merge(merged, report.latency)
    }),
    queue_samples:,
    memory_words_per_unit: int.to_float(memory_words)
      /. int.to_float(workload.players + workload.creatures),
    pace: case owners_pace, list.length(reports) == list.length(players) {
      KeptUp, False -> PlayersFellBehind
      KeptUp, True | FellBehind, _ | PlayersFellBehind, _ -> owners_pace
    },
  )
}

fn start_prototype(
  prototype prototype: Prototype,
  workload workload: Workload,
  key key: reference.Reference,
) -> Result(actor.Started(Owner), actor.StartError) {
  case prototype {
    PerUnit -> per_unit.start(workload, key)
    MapProcess(planted:) -> map_process.start(workload, key, planted)
  }
}

/// The summed queue of the owners' processes, taken once each interval for
/// the length of the measured stretch.
fn sample_queues(door: Owner, timing: Timing) -> List(Int) {
  let samples =
    timing.measure_milliseconds / timing.sample_interval_milliseconds
  int.range(0, samples, [], fn(taken, _) {
    process.sleep(timing.sample_interval_milliseconds)
    let queue =
      door.owner_processes()
      |> list.map(fn(pid) {
        measurement.message_queue_length(pid) |> result.unwrap(0)
      })
      |> int.sum
    [queue, ..taken]
  })
  |> list.reverse
}
