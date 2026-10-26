//// One load run: a prototype and its players started together, a warm-up,
//// a measured stretch, and what the run counted.

import genesis_prime/topology/latency.{type Histogram}
import genesis_prime/topology/map_process.{type PlantedCost}
import genesis_prime/topology/workload.{type Workload}

/// How long the load runs before anything is counted, in milliseconds.
pub const warm_up_milliseconds = 5000

/// How long the measured stretch lasts, in milliseconds.
pub const measure_milliseconds = 30_000

/// How often the owners' queues are sampled, in milliseconds.
pub const sample_interval_milliseconds = 1000

/// The first sample, counted from the start of the measured stretch, that
/// counts toward falling behind.
pub const first_judged_sample = 10

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
}

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
pub fn load_per_second(workload: Workload) -> Int {
  todo as "body in the build commit"
}

/// Whether the owners kept up: from `first_judged_sample` on, no sample of the
/// owners' summed queue may exceed `load_per_second`.
pub fn pace(queue_samples: List(Int), load_per_second: Int) -> Pace {
  todo as "body in the build commit"
}

/// The name of a prototype as it is printed in a table.
pub fn name_of(prototype: Prototype) -> String {
  todo as "body in the build commit"
}

/// Runs the load once, with `schedulers` schedulers online: starts one
/// supervisor with the prototype first and the players' factory after it,
/// tells each player to begin, which joins its connection, runs
/// the warm-up, counts through the measured stretch while sampling the
/// owners' summed queue each interval, and stops everything. The spawn list is
/// kept under a key made for the run and erased at the end.
pub fn run(
  prototype: Prototype,
  workload: Workload,
  schedulers: Int,
) -> RunResult {
  todo as "body in the build commit"
}
