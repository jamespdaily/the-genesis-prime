//// The load run's sampler: what a node's runtime shows about how a load is
//// going, read directly and handed to the ramp once a second. No package does
//// it: Erlang's `telemetry` only passes events along, and its poller cannot
//// see a process that has no name, such as a connection's shell.
////
//// One sample holds, for the node it is taken on: the monotonic time; the
//// connections each watched listener holds; every process with messages
//// waiting, with its mailbox and heap (the heap is in words); the largest heap
//// of any process; the memory the VM holds; the schedulers' busy and passed
//// wall time, summed over the online normal schedulers (two samples give the
//// share of the cores used between them, `use_between`); the run queue; and,
//// for the server, how many store workers are waiting and how long a store
//// worker takes to start.
////
//// A store worker is one process an ask starts under the store's factory
//// supervisor, and the pool lets only `pool_size` of them query at once, so
//// those running beyond it wait for a connection. Starting one is a
//// supervisor call with no timeout, so the sample times the start of the
//// readiness probe's worker, which is the same call.
////
//// `start` starts counting the lines logged at warning level or
//// above; every sample after it carries the count.

import genesis_prime/store/worker.{type Job}
import gleam/erlang/process.{type Name, type Pid}
import gleam/int
import gleam/list
import gleam/otp/factory_supervisor

/// A process that has messages waiting.
pub type Waiting {
  Waiting(pid: Pid, mailbox: Int, heap_words: Int, described: String)
}

/// What one reading of a node showed.
pub type Sample {
  Sample(
    at_ms: Int,
    connections: List(Int),
    waiting: List(Waiting),
    largest_heap_words: Int,
    memory_bytes: Int,
    busy_us: Int,
    total_us: Int,
    run_queue: Int,
    store_waiting: Int,
    worker_start_us: Int,
    log_lines: Int,
  )
}

/// What the server's sample watches beyond the node: its listeners, in the
/// order their connection counts are given, and its store.
pub type Watch {
  Watch(
    listeners: List(Name(Nil)),
    store: Name(factory_supervisor.Message(Job, Nil)),
    pool_size: Int,
  )
}

/// The node as it is now, with no listener or store.
pub fn take_node() -> Sample {
  let #(waiting, largest_heap_words) = scan()
  let #(busy_us, total_us) = scheduler_time()
  Sample(
    at_ms: microseconds() / 1000,
    connections: [],
    waiting: list.map(waiting, fn(found) {
      Waiting(
        pid: found.0,
        mailbox: found.1,
        heap_words: found.2,
        described: found.3,
      )
    }),
    largest_heap_words:,
    memory_bytes: memory(),
    busy_us:,
    total_us:,
    run_queue: run_queue(),
    store_waiting: 0,
    worker_start_us: 0,
    log_lines: log_lines(),
  )
}

/// The node as it is now, with the watched listeners' connections and the
/// store's waiting workers, and the time a worker takes to start.
pub fn take(watch: Watch) -> Sample {
  let started_at = microseconds()
  let _worker = worker.probe(store: watch.store, reply: fn(_probed) { Nil })
  let worker_start_us = microseconds() - started_at
  Sample(
    ..take_node(),
    connections: list.map(watch.listeners, connections),
    store_waiting: int.max(0, workers(watch.store) - watch.pool_size),
    worker_start_us:,
  )
}

/// The share of the node's cores that were in use between two of its samples,
/// from 0.0 to 1.0.
pub fn use_between(first first: Sample, last last: Sample) -> Float {
  let passed = last.total_us - first.total_us
  case passed > 0 {
    True -> int.to_float(last.busy_us - first.busy_us) /. int.to_float(passed)
    False -> 0.0
  }
}

/// The monotonic clock in microseconds.
@external(erlang, "load_sample_ffi", "microseconds")
pub fn microseconds() -> Int

/// The monotonic clock in milliseconds.
pub fn milliseconds() -> Int {
  microseconds() / 1000
}

/// Starts counting the lines logged at warning level or above on this node.
@external(erlang, "load_sample_ffi", "start")
pub fn start() -> Nil

@external(erlang, "load_sample_ffi", "log_lines")
fn log_lines() -> Int

@external(erlang, "load_sample_ffi", "scan")
fn scan() -> #(List(#(Pid, Int, Int, String)), Int)

@external(erlang, "load_sample_ffi", "scheduler_time")
fn scheduler_time() -> #(Int, Int)

@external(erlang, "load_sample_ffi", "connections")
fn connections(listener: Name(Nil)) -> Int

@external(erlang, "load_sample_ffi", "workers")
fn workers(store: Name(factory_supervisor.Message(Job, Nil))) -> Int

@external(erlang, "load_sample_ffi", "memory")
fn memory() -> Int

@external(erlang, "load_sample_ffi", "run_queue")
fn run_queue() -> Int
