//// A short run of the topology benchmark's harness, to show in seconds that
//// both prototypes start, carry the load and report: one run each at 20
//// players and 200 creatures on all the cores, with short timing.
////
//// Run it with `gleam run -m genesis_prime/topology/smoke`.

import genesis_prime/topology/latency
import genesis_prime/topology/map_process
import genesis_prime/topology/measurement
import genesis_prime/topology/run.{type Prototype, type RunResult}
import genesis_prime/topology/workload.{Workload}
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/string

/// Runs each prototype once and prints what the run counted.
pub fn main() -> Nil {
  measurement.enable_scheduler_wall_time()
  let cores = measurement.core_count()
  let timing =
    run.Timing(
      warm_up_milliseconds: 200,
      measure_milliseconds: 1000,
      sample_interval_milliseconds: 100,
    )
  let prototypes = [run.PerUnit, run.MapProcess(map_process.NoPlantedCost)]
  list.each(prototypes, fn(prototype) {
    print(
      prototype,
      run.run(
        prototype,
        Workload(..workload.default(), players: 20, creatures: 200),
        cores,
        timing,
      ),
    )
  })
}

fn print(prototype: Prototype, result: RunResult) -> Nil {
  io.println("== " <> run.name_of(prototype))
  io.println("players: " <> int.to_string(result.players))
  io.println("creatures: " <> int.to_string(result.creatures))
  io.println("schedulers: " <> int.to_string(result.schedulers))
  io.println("moves sent: " <> int.to_string(result.moves_sent))
  io.println("updates received: " <> int.to_string(result.updates_received))
  io.println("busy microseconds: " <> int.to_string(result.busy_microseconds))
  io.println("messages handled: " <> int.to_string(result.messages_handled))
  io.println(
    "latency: count "
    <> int.to_string(latency.count(result.latency))
    <> " p50 "
    <> int.to_string(latency.percentile(result.latency, 50.0))
    <> " p99 "
    <> int.to_string(latency.percentile(result.latency, 99.0))
    <> " max "
    <> int.to_string(latency.maximum(result.latency))
    <> " microseconds",
  )
  io.println(
    "queue samples: "
    <> string.join(list.map(result.queue_samples, int.to_string), " "),
  )
  io.println(
    "memory words per unit: "
    <> float.to_string(float.to_precision(result.memory_words_per_unit, 2)),
  )
  io.println(
    "pace: "
    <> case result.pace {
      run.KeptUp -> "KeptUp"
      run.FellBehind -> "FellBehind"
    },
  )
}
