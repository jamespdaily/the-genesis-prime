//// One load run: one or more maps of a prototype and their players started
//// together, a warm-up, a measured stretch, and what the run counted.

import genesis_prime/topology/latency.{type Histogram}
import genesis_prime/topology/map_process.{type Sending}
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/per_unit
import genesis_prime/topology/workload.{type Workload}
import gleam/erlang/reference
import gleam/list
import gleam/otp/actor

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

/// Which prototype a run measures.
pub type Prototype {
  /// One process per unit.
  PerUnit
  /// One map process, and who sends its deliveries: the map process itself is
  /// prototype B, a pool of senders is prototype C.
  MapProcess(sending: Sending)
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
    MapProcess(sending: map_process.SendsItself) -> "B one map process"
    MapProcess(sending: map_process.SenderPool) ->
      "C map process with sender pool"
  }
}

/// Runs the load once, with `schedulers` schedulers online, on `maps` maps
/// side by side, and returns what it counted. `workload` is the load of one
/// map; map `n` (counted from 0) runs `workload.for_map(workload, n)`, so the
/// maps start from different spawn lists. A run starts one supervisor with the
/// maps' prototypes first and the players' factory after them, tells each
/// player to begin on its own map's owner, which joins its connection, runs
/// the warm-up, counts through the measured stretch while sampling each map's
/// owners' summed queue each interval, and stops everything. Each map's spawn
/// list is kept under a key made for the run and erased at the end. One map is
/// a run of the prototype alone.
pub fn run(
  prototype prototype: Prototype,
  workload workload: Workload,
  maps maps: Int,
  schedulers schedulers: Int,
  timing timing: Timing,
) -> RunResult {
  todo as "body in the build commit"
}

fn start_prototype(
  prototype prototype: Prototype,
  workload workload: Workload,
  key key: reference.Reference,
) -> Result(actor.Started(Owner), actor.StartError) {
  case prototype {
    PerUnit -> per_unit.start(workload, key)
    MapProcess(sending:) -> map_process.start(workload, key, sending)
  }
}

/// How long the players together have to report after a run whose owners
/// had the given pace, `FellBehind` when any map's owners fell behind. A pace of `PlayersFellBehind` is never an argument:
/// it is decided from the reports this deadline collects.
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
  todo as "body in the build commit"
}
