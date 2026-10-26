//// One load run: one or more maps of a prototype and their players started
//// together, a warm-up, a measured stretch, and what the run counted.

import genesis_prime/topology/heap_limit.{type HeapLimits}
import genesis_prime/topology/heap_sampler.{type Sampled}
import genesis_prime/topology/latency.{type Histogram}
import genesis_prime/topology/map_process.{type Sending}
import genesis_prime/topology/measurement
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/per_unit
import genesis_prime/topology/player.{type Player, type Report}
import genesis_prime/topology/unit
import genesis_prime/topology/workload.{type Workload}
import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/option.{type Option}
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
    /// The first sample, counted from the start of the measured stretch, that
    /// counts toward falling behind: the samples before it are the owners
    /// catching up with the start of the load.
    first_judged_sample: Int,
  )
}

/// The timing of a full run: 5 seconds of warm-up, a measured stretch of 30
/// seconds and a sample every second, judged from the tenth.
pub const full_timing =
  Timing(
    warm_up_milliseconds: 5000,
    measure_milliseconds: 30_000,
    sample_interval_milliseconds: 1000,
    first_judged_sample: 10,
  )

/// The timing of a short run: 3 seconds of warm-up, a measured stretch of 15
/// seconds and a sample every second, judged from the fifth.
pub const short_timing =
  Timing(
    warm_up_milliseconds: 3000,
    measure_milliseconds: 15_000,
    sample_interval_milliseconds: 1000,
    first_judged_sample: 5,
  )

/// Whether a run reads the heap of each owner process.
pub type Sampling {
  /// The run reads only the owners' queues, once each timing interval, so its
  /// conditions are those of a run before the heap sampler existed.
  NotSampled
  /// The run also starts the heap sampler with the prototypes. Its kills and
  /// replacements cover the whole run, warm-up included, and its peaks cover
  /// the measured stretch. Only a map process prototype is sampled: the owners
  /// of `PerUnit` are one process for each unit, too many to read every 100
  /// milliseconds without disturbing the run, so `run` refuses it with
  /// `PerUnit`.
  SampleHeaps
}

/// Which prototype a run measures.
pub type Prototype {
  /// One process per unit.
  PerUnit
  /// One map process, who sends its deliveries, and the heap limits of its
  /// processes: the map process itself sending is prototype B, a pool of
  /// senders is prototype C. `heap_limit.no_limits` sets none.
  MapProcess(sending: Sending, heap_limits: HeapLimits)
}

/// Whether the owners kept up with the load.
pub type Pace {
  /// No judged sample's queue exceeded what the load sends in one second.
  KeptUp
  /// A judged sample's queue exceeded what the load sends in one second.
  FellBehind
  /// The owners kept up, but a player did not report: its process had ended,
  /// or the updates sent to it outran it and it did not answer within
  /// `report_deadline_milliseconds`. The
  /// choosing rule's ceiling reads only the owners, so this counts as kept up
  /// there, and its latency covers only the players that reported.
  PlayersFellBehind
}

/// How long the players together have to report after the measured stretch
/// when the owners kept up.
const report_deadline_kept_up_milliseconds = 30_000

/// How long the players together have to report after the measured stretch
/// when the owners fell behind: their mailboxes are full of updates that
/// arrive late or not at all, so waiting longer adds nothing.
const report_deadline_fell_behind_milliseconds = 5000

/// What one run counted over its measured stretch. With several maps, the
/// player and creature counts, the moves, updates, messages, busy time and
/// memory per unit are over all maps together, the latency is every map's
/// merged, and `queue_samples` holds each sample's queue summed over all maps.
pub type RunResult {
  RunResult(
    prototype: Prototype,
    /// How many maps ran side by side.
    maps: Int,
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
    /// The pace of each map, in map order, judged from that map's own owners'
    /// queue against that map's own load and from that map's own players'
    /// reports.
    map_paces: List(Pace),
    /// `FellBehind` when any map fell behind, otherwise `PlayersFellBehind`
    /// when any map's players did not all report, otherwise `KeptUp`.
    pace: Pace,
    /// What the heap sampler found, over all maps' owners together: the peaks
    /// over the measured stretch, the kills and replacements over the whole
    /// run; none when the run was `NotSampled`.
    sampled: Option(Sampled),
  )
}

/// The messages the load sends to one map's owners in one second: every
/// player's moves and attack, and every creature's think.
fn load_per_second(workload: Workload) -> Int {
  workload.players * { workload.moves_per_second + 1 } + workload.creatures
}

/// Whether one map's owners kept up: from the timing's first judged sample on,
/// no sample of that map's owners' summed queue may exceed that map's
/// `load_per_second`.
fn pace(
  queue_samples queue_samples: List(Int),
  load_per_second load_per_second: Int,
  timing timing: Timing,
) -> Pace {
  let judged = list.drop(queue_samples, timing.first_judged_sample - 1)
  case list.any(judged, fn(queue) { queue > load_per_second }) {
    True -> FellBehind
    False -> KeptUp
  }
}

/// The name of a prototype as it is printed in a table.
pub fn name_of(prototype: Prototype) -> String {
  case prototype {
    PerUnit -> "A one process per unit"
    MapProcess(sending: map_process.SendsItself, ..) -> "B one map process"
    MapProcess(sending: map_process.SenderPool, ..) ->
      "C map process with sender pool"
  }
}

/// One map of a run: its workload, the key its spawn list is kept under, the
/// units it starts with and the owner its players act through.
type MapRun {
  MapRun(
    workload: Workload,
    key: reference.Reference,
    spawn_list: List(unit.Unit),
    door: Owner,
    players: List(Player),
  )
}

/// Runs the load once, with `schedulers` schedulers online, on `maps` maps
/// side by side, and returns what it counted. `workload` is the load of one
/// map; map `n` (counted from 0) runs `workload.for_map(workload, n)`, so the
/// maps start from different spawn lists. A run starts one supervisor with the
/// maps' prototypes first and the players' factory after them, tells each
/// player to begin on its own map's owner, which joins its connection, runs
/// the warm-up, counts through the measured stretch while sampling each map's
/// owners' summed queue each interval and, when `sampling` is `SampleHeaps`,
/// the heap and queue of each owner process every 100 milliseconds (from the
/// start of the run, with the peaks forgotten at the measured stretch), and
/// stops everything. Each map's spawn list is kept under a key made for the
/// run and erased at the end. One map is a run of the prototype alone.
pub fn run(
  prototype prototype: Prototype,
  workload workload: Workload,
  maps maps: Int,
  schedulers schedulers: Int,
  timing timing: Timing,
  sampling sampling: Sampling,
) -> RunResult {
  assert maps >= 1 as "a run has at least one map"
  let sampling_is_possible = case sampling, prototype {
    SampleHeaps, PerUnit -> False
    SampleHeaps, MapProcess(..)
    | NotSampled, PerUnit
    | NotSampled, MapProcess(..)
    -> True
  }
  assert sampling_is_possible
    as "a run of the one-process-per-unit prototype cannot sample heaps"
  measurement.set_schedulers_online(schedulers)
  let planned =
    int.range(0, maps, [], fn(taken, map_index) {
      let map_workload = workload.for_map(workload:, map_index:)
      let spawn_list = workload.spawn_list(map_workload)
      let key = reference.new()
      measurement.put_spawn_list(
        key,
        dict.from_list(list.map(spawn_list, fn(unit) { #(unit.id, unit) })),
      )
      [#(map_workload, key, spawn_list), ..taken]
    })
    |> list.reverse
  let door_ready = process.new_subject()
  let factory_ready = process.new_subject()
  let prototype_children =
    list.map(planned, fn(plan) {
      let #(map_workload, key, _) = plan
      supervision.supervisor(fn() {
        start_prototype(prototype:, workload: map_workload, key:)
      })
      |> owner.reporting(door_ready)
    })
  let players_child =
    player.factory(workload)
    |> factory_supervisor.supervised
    |> owner.reporting(factory_ready)
  let assert Ok(supervisor) =
    list.fold(
      prototype_children,
      static_supervisor.new(static_supervisor.RestForOne),
      static_supervisor.add,
    )
    |> static_supervisor.add(players_child)
    |> static_supervisor.start
    as "the run's supervisor did not start"
  let doors =
    list.map(planned, fn(_) {
      let assert Ok(door) = process.receive(door_ready, 5000)
        as "a prototype did not report its owner"
      door
    })
  let assert Ok(factory) = process.receive(factory_ready, 5000)
    as "the players' supervisor did not report itself"
  let map_runs =
    list.zip(planned, doors)
    |> list.map(fn(pair) {
      let #(#(map_workload, key, spawn_list), door) = pair
      let players =
        spawn_list
        |> list.filter(fn(unit) { unit.kind == unit.Player })
        |> list.map(fn(unit) {
          let assert Ok(started) = factory_supervisor.start_child(factory, unit)
            as "a player did not start"
          started.data
        })
      MapRun(workload: map_workload, key:, spawn_list:, door:, players:)
    })
  let players = list.flat_map(map_runs, fn(map_run) { map_run.players })
  let sampler = case sampling {
    SampleHeaps -> option.Some(heap_sampler.start(doors))
    NotSampled -> option.None
  }
  list.each(map_runs, fn(map_run) {
    list.each(map_run.players, player.begin(_, map_run.door))
  })
  process.sleep(timing.warm_up_milliseconds)

  list.each(players, player.reset_counts)
  let handled_before = messages_handled(doors)
  let scheduler_before = measurement.scheduler_time()
  case sampler {
    option.Some(sampler) -> heap_sampler.begin_measuring(sampler)
    option.None -> Nil
  }
  let samples = sample_queues(doors, timing)
  let scheduler_after = measurement.scheduler_time()
  let handled_after = messages_handled(doors)
  let sampled = option.map(sampler, heap_sampler.stop)
  let memory_words =
    doors
    |> list.map(fn(door) { door.memory_words() })
    |> int.sum
  let queues_by_map = case samples {
    [] -> list.map(doors, fn(_) { [] })
    [_, ..] -> list.transpose(samples)
  }
  let owners_paces =
    list.map2(map_runs, queues_by_map, fn(map_run, queue_samples) {
      pace(
        queue_samples:,
        load_per_second: load_per_second(map_run.workload),
        timing:,
      )
    })
  let owners_pace = case list.contains(owners_paces, FellBehind) {
    True -> FellBehind
    False -> KeptUp
  }
  let reports_by_map =
    collect_reports(
      players_by_map: list.map(map_runs, fn(map_run) { map_run.players }),
      within_milliseconds: report_deadline_milliseconds(owners_pace),
    )
  let reports = list.flatten(reports_by_map)
  owner.stop_supervisor(supervisor.pid)
  list.each(map_runs, fn(map_run) { measurement.erase_spawn_list(map_run.key) })

  let map_paces =
    list.zip(list.zip(owners_paces, reports_by_map), map_runs)
    |> list.map(fn(found) {
      let #(#(map_owners_pace, map_reports), map_run) = found
      case
        map_owners_pace,
        list.length(map_reports) == list.length(map_run.players)
      {
        KeptUp, False -> PlayersFellBehind
        KeptUp, True | FellBehind, _ | PlayersFellBehind, _ -> map_owners_pace
      }
    })
  let units =
    int.sum(
      list.map(map_runs, fn(map_run) {
        map_run.workload.players + map_run.workload.creatures
      }),
    )
  RunResult(
    prototype:,
    maps:,
    players: int.sum(
      list.map(map_runs, fn(map_run) { map_run.workload.players }),
    ),
    creatures: int.sum(
      list.map(map_runs, fn(map_run) { map_run.workload.creatures }),
    ),
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
    queue_samples: list.map(samples, int.sum),
    memory_words_per_unit: int.to_float(memory_words) /. int.to_float(units),
    map_paces:,
    pace: run_pace(map_paces),
    sampled:,
  )
}

/// Asks every player for its counts and collects the answers, one list for
/// each list of players, in the order of `players_by_map`. All players are
/// asked first, and the answers have `within_milliseconds` together. A player
/// that has not answered by then, or whose process has ended, is left out; a
/// monitor shows the end at once, so a player that crashed is not waited for.
pub fn collect_reports(
  players_by_map players_by_map: List(List(Player)),
  within_milliseconds within_milliseconds: Int,
) -> List(List(Report)) {
  let asked =
    list.map(players_by_map, fn(players) {
      list.map(players, player.ask_report)
    })
  let deadline =
    measurement.monotonic_microseconds() / 1000 + within_milliseconds
  list.map(asked, fn(replies) {
    list.map(replies, fn(reply) {
      let left = deadline - measurement.monotonic_microseconds() / 1000
      player.await_report(reply, within_milliseconds: int.max(left, 0))
    })
    |> result.values
  })
}

/// The pace of the whole run: `FellBehind` when any map fell behind, otherwise
/// `PlayersFellBehind` when any map's players did not all report, otherwise
/// `KeptUp`.
fn run_pace(map_paces: List(Pace)) -> Pace {
  case
    list.contains(map_paces, FellBehind),
    list.contains(map_paces, PlayersFellBehind)
  {
    True, _ -> FellBehind
    False, True -> PlayersFellBehind
    False, False -> KeptUp
  }
}

/// The messages every map's owners have handled since their prototypes started,
/// added up.
fn messages_handled(doors: List(Owner)) -> Int {
  int.sum(list.map(doors, fn(door) { door.messages_handled() }))
}

fn start_prototype(
  prototype prototype: Prototype,
  workload workload: Workload,
  key key: reference.Reference,
) -> Result(actor.Started(Owner), actor.StartError) {
  case prototype {
    PerUnit -> per_unit.start(workload, key)
    MapProcess(sending:, heap_limits:) ->
      map_process.start(workload, key, sending, heap_limits)
  }
}

/// How long the players together have to report after a run whose owners
/// had the given pace: `FellBehind` when the owners of any map fell behind. A
/// pace of `PlayersFellBehind` is never an argument: it is decided from the
/// reports this deadline collects.
fn report_deadline_milliseconds(owners_pace: Pace) -> Int {
  case owners_pace {
    KeptUp | PlayersFellBehind -> report_deadline_kept_up_milliseconds
    FellBehind -> report_deadline_fell_behind_milliseconds
  }
}

/// The summed queue of each map's owners' processes, taken once each interval
/// for the length of the measured stretch: one list per sample, holding each
/// map's queue in map order. `doors` holds each map's owner in map order.
fn sample_queues(doors: List(Owner), timing: Timing) -> List(List(Int)) {
  let samples =
    timing.measure_milliseconds / timing.sample_interval_milliseconds
  int.range(0, samples, [], fn(taken, _) {
    process.sleep(timing.sample_interval_milliseconds)
    let queues =
      list.map(doors, fn(door) {
        door.owner_processes()
        |> list.map(fn(pid) {
          measurement.message_queue_length(pid) |> result.unwrap(0)
        })
        |> int.sum
      })
    [queues, ..taken]
  })
  |> list.reverse
}
