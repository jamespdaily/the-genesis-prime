//// The runtime's own clock and counters, read by the topology benchmark. Each
//// function calls the one Erlang file `dev/topology_ffi.erl`.

import genesis_prime/topology/unit.{type Unit}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference.{type Reference}
import gleam/list
import gleam/result

/// A counter many processes add to at once, without a lock or a message.
pub type Counter

/// Scheduler time in microseconds, summed over the schedulers online: the
/// time they ran processes, and the time they existed.
pub type SchedulerTime {
  SchedulerTime(busy_microseconds: Int, total_microseconds: Int)
}

/// The monotonic clock, in microseconds. It can be negative, so 0 never means
/// none.
@external(erlang, "topology_ffi", "monotonic_microseconds")
pub fn monotonic_microseconds() -> Int

/// Starts the runtime's scheduler time accounting. Call it once before the
/// first `scheduler_time`; calling it again changes nothing.
@external(erlang, "topology_ffi", "enable_scheduler_wall_time")
pub fn enable_scheduler_wall_time() -> Nil

/// Runs the calling process at high priority, so a harness that samples and
/// stops a run is not starved by the load it measures when only one
/// scheduler is online.
@external(erlang, "topology_ffi", "set_high_priority")
pub fn set_high_priority() -> Nil

/// The arguments given after `--` on the command line.
@external(erlang, "topology_ffi", "plain_arguments")
pub fn plain_arguments() -> List(String)

/// The scheduler time since accounting started, from the runtime's
/// `scheduler_wall_time`.
pub fn scheduler_time() -> SchedulerTime {
  let times = scheduler_wall_time()
  SchedulerTime(
    busy_microseconds: list.fold(times, 0, fn(sum, time) { sum + time.1 }),
    total_microseconds: list.fold(times, 0, fn(sum, time) { sum + time.2 }),
  )
}

/// Each scheduler's id, busy time and total time, in microseconds.
@external(erlang, "topology_ffi", "scheduler_wall_time")
fn scheduler_wall_time() -> List(#(Int, Int, Int))

@external(erlang, "topology_ffi", "process_memory_words")
fn memory_words_of(pid: Pid) -> Result(Int, Nil)

@external(erlang, "topology_ffi", "message_queue_length")
fn queue_length_of(pid: Pid) -> Result(Int, Nil)

/// Sets how many schedulers are online, the same as starting the runtime with
/// that many.
@external(erlang, "topology_ffi", "set_schedulers_online")
pub fn set_schedulers_online(count: Int) -> Nil

/// How many cores the machine has.
@external(erlang, "topology_ffi", "core_count")
pub fn core_count() -> Int

/// How many schedulers are online now.
@external(erlang, "topology_ffi", "schedulers_online")
pub fn schedulers_online() -> Int

/// The words of memory a process holds, or an error when it is not alive.
pub fn process_memory_words(pid: Pid) -> Result(Int, Nil) {
  memory_words_of(pid)
}

/// How many messages wait in a process's mailbox, or an error when it is not
/// alive.
pub fn message_queue_length(pid: Pid) -> Result(Int, Nil) {
  queue_length_of(pid)
}

/// What one reading of a process showed: the words its heap, stack and
/// waiting messages hold together (`total_heap_size`), and how many messages
/// wait in its mailbox.
pub type ProcessSize {
  ProcessSize(heap_words: Int, queue: Int)
}

@external(erlang, "topology_ffi", "process_heap_and_queue")
fn heap_and_queue_of(pid: Pid) -> Result(#(Int, Int), Nil)

/// Both sizes of a process read in one call, or an error when it is not alive.
pub fn process_size(pid: Pid) -> Result(ProcessSize, Nil) {
  use #(heap_words, queue) <- result.map(heap_and_queue_of(pid))
  ProcessSize(heap_words:, queue:)
}

/// Bytes the runtime holds in binaries, outside every process heap
/// (`erlang:memory(binary)`).
@external(erlang, "topology_ffi", "binary_bytes")
pub fn binary_bytes() -> Int

/// Bytes the runtime holds in ETS tables (`erlang:memory(ets)`).
@external(erlang, "topology_ffi", "ets_bytes")
pub fn ets_bytes() -> Int

/// Sets the calling process's `max_heap_size` to `words` words with kill on
/// and the error logger on, and shared binaries not counted. `words` is at
/// least 1: the runtime reads 0 as no limit.
@external(erlang, "topology_ffi", "set_max_heap_size")
pub fn set_max_heap_size(words words: Int) -> Nil

/// A counter at 0.
@external(erlang, "topology_ffi", "new_counter")
pub fn new_counter() -> Counter

/// Adds 1 to a counter.
@external(erlang, "topology_ffi", "increment")
pub fn increment(counter: Counter) -> Nil

/// What a counter holds.
@external(erlang, "topology_ffi", "counter_value")
pub fn counter_value(counter: Counter) -> Int

/// Keeps a spawn list, keyed by unit id, in a persistent term under `key`, as
/// one large term every process reads without copying it. The key is a start
/// argument, so runs side by side share nothing.
@external(erlang, "topology_ffi", "put_spawn_list")
pub fn put_spawn_list(key: Reference, spawn_list: Dict(Int, Unit)) -> Nil

/// The spawn list kept under `key`. A key with no list is a bug and crashes.
@external(erlang, "topology_ffi", "get_spawn_list")
pub fn spawn_list(key: Reference) -> Dict(Int, Unit)

/// Removes the spawn list kept under `key`.
@external(erlang, "topology_ffi", "erase_spawn_list")
pub fn erase_spawn_list(key: Reference) -> Nil
