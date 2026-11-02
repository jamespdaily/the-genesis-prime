//// The load run's sampler: what a node's runtime shows about how a load is
//// going, read directly and handed to the ramp once a second. No package does
//// it: Erlang's `telemetry` only passes events along, and its poller cannot
//// see a process that has no name, such as a connection's shell.
////
//// One sample holds, for the node it is taken on: the monotonic time; every
//// process with messages waiting, with its mailbox and heap (the heap is in
//// words); the largest heap of any process; the memory the VM holds; the schedulers' busy and passed
//// wall time, summed over the online normal schedulers (two samples give the
//// share of the cores used between a node's first and last, `use_between`); the
//// run queue; and, for the server only (`ServerReading`), the connections each
//// listener holds, how many store workers are waiting and how long a store
//// worker takes to start.
////
//// A store worker is one process an ask starts under the store's factory
//// supervisor, and the pool lets only `pool_size` of them query at once, so
//// those running beyond it wait for a connection. The sample counts the
//// workers before it starts a probe worker of its own, so its own is not
//// counted. Starting a worker is a supervisor call with no timeout, so the
//// sample times the start of that probe worker, which is the same call.
////
//// `start` starts counting the lines logged at warning level or
//// above; every sample after it carries the count.

import genesis_prime/server.{type Settings}
import genesis_prime/step/runtime
import genesis_prime/store/worker
import gleam/erlang/process.{type Name, type Pid}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// A process that has messages waiting.
pub type Waiting {
  Waiting(pid: Pid, mailbox: Int, heap_words: Int, described: String)
}

/// What a reading of the server shows that a node of clients has no listener
/// or store for: the connections each of the STS, auth and game listeners
/// holds, in that order, the store's workers waiting for the pool, and the
/// microseconds a worker took to start.
pub type ServerReading {
  ServerReading(
    connections: List(Int),
    store_waiting: Int,
    worker_start_us: Int,
  )
}

/// What one reading of a node showed; `server` is `None` for a node that is
/// not the server.
pub type Sample {
  Sample(
    at_ms: Int,
    waiting: List(Waiting),
    largest_heap_words: Int,
    memory_bytes: Int,
    busy_us: Int,
    total_us: Int,
    run_queue: Int,
    server: Option(ServerReading),
    log_lines: Int,
  )
}

/// The node as it is now, with no listener or store.
pub fn take_node() -> Sample {
  let #(waiting, largest_heap_words) = scan()
  let #(busy_us, total_us) = scheduler_time()
  Sample(
    at_ms: runtime.now().monotonic_ms,
    waiting:,
    largest_heap_words:,
    memory_bytes: memory(Total),
    busy_us:,
    total_us:,
    run_queue: statistics(TotalRunQueueLengths),
    server: None,
    log_lines: log_lines(),
  )
}

/// The node as it is now, with the connections of the server's STS, auth and
/// game listeners in that order, the store's workers waiting for the pool, and
/// the time a worker takes to start.
pub fn take(settings: Settings) -> Sample {
  let listeners = [
    settings.login.sts.listener,
    settings.login.auth.listener,
    settings.game.listener,
  ]
  let store_waiting =
    int.max(0, workers(settings.store) - settings.pool.pool_size)
  let started_at = monotonic_time(Microsecond)
  let _worker = worker.probe(store: settings.store, reply: fn(_probed) { Nil })
  let worker_start_us = monotonic_time(Microsecond) - started_at
  Sample(
    ..take_node(),
    server: Some(ServerReading(
      connections: list.map(listeners, fn(listener) {
        list.length(procs(listener, Connections))
      }),
      store_waiting:,
      worker_start_us:,
    )),
  )
}

/// The connections each listener held when the sample was taken, none for a
/// sample of a node that is not the server.
pub fn connections(sample sample: Sample) -> List(Int) {
  option.map(sample.server, fn(reading) { reading.connections })
  |> option.unwrap([])
}

/// How many store workers were waiting for the pool, 0 for a sample of a node
/// that is not the server.
pub fn store_waiting(sample sample: Sample) -> Int {
  option.map(sample.server, fn(reading) { reading.store_waiting })
  |> option.unwrap(0)
}

/// The microseconds a store worker took to start, 0 for a sample of a node
/// that is not the server.
pub fn worker_start_us(sample sample: Sample) -> Int {
  option.map(sample.server, fn(reading) { reading.worker_start_us })
  |> option.unwrap(0)
}

/// A sample list's first and last.
fn ends(samples: List(Sample)) -> Result(#(Sample, Sample), Nil) {
  use first <- result.try(list.first(samples))
  use last <- result.map(list.last(samples))
  #(first, last)
}

/// The share of the node's cores that were in use between a node's first and
/// last sample, from 0.0 to 1.0, or 0.0 for fewer than two.
pub fn use_between(samples: List(Sample)) -> Float {
  case ends(samples) {
    Ok(#(first, last)) if last.total_us > first.total_us ->
      int.to_float(last.busy_us - first.busy_us)
      /. int.to_float(last.total_us - first.total_us)
    _ -> 0.0
  }
}

/// The warning and error lines logged between a node's first and last sample.
pub fn log_lines_between(samples: List(Sample)) -> Int {
  ends(samples)
  |> result.map(fn(ends) { { ends.1 }.log_lines - { ends.0 }.log_lines })
  |> result.unwrap(0)
}

/// The monotonic clock in microseconds.
pub fn microseconds() -> Int {
  monotonic_time(Microsecond)
}

/// Starts the wall time and the line counting on this node.
@external(erlang, "load_sample_ffi", "start")
pub fn start() -> Nil

@external(erlang, "load_sample_ffi", "log_lines")
fn log_lines() -> Int

@external(erlang, "load_sample_ffi", "scan")
fn scan() -> #(List(Waiting), Int)

@external(erlang, "load_sample_ffi", "scheduler_time")
fn scheduler_time() -> #(Int, Int)

/// The atoms the Erlang calls below are given, which a Gleam constructor
/// compiles to.
type Unit {
  Microsecond
}

type MemoryKind {
  Total
}

type Statistic {
  TotalRunQueueLengths
}

type ProcessKind {
  Connections
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: Unit) -> Int

@external(erlang, "erlang", "memory")
fn memory(kind: MemoryKind) -> Int

@external(erlang, "erlang", "statistics")
fn statistics(kind: Statistic) -> Int

/// The connection processes of a Ranch listener.
@external(erlang, "ranch", "procs")
fn procs(listener: Name(Nil), kind: ProcessKind) -> List(Pid)

/// How many workers the store's factory supervisor has running.
@external(erlang, "load_sample_ffi", "workers")
fn workers(store: Name(message)) -> Int
