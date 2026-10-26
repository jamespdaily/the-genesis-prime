//// The runtime's own clock and counters, read by the topology benchmark. Each
//// function calls the one Erlang file `dev/topology_ffi.erl`.

import genesis_prime/topology/unit.{type Unit}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference.{type Reference}

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

/// The scheduler time since accounting started, from the runtime's
/// `scheduler_wall_time`.
pub fn scheduler_time() -> SchedulerTime {
  todo as "body in the build commit"
}

/// Sets how many schedulers are online, the same as starting the runtime with
/// that many.
@external(erlang, "topology_ffi", "set_schedulers_online")
pub fn set_schedulers_online(count: Int) -> Nil

/// How many cores the machine has.
@external(erlang, "topology_ffi", "core_count")
pub fn core_count() -> Int

/// The words of memory a process holds, or an error when it is not alive.
pub fn process_memory_words(pid: Pid) -> Result(Int, Nil) {
  todo as "body in the build commit"
}

/// How many messages wait in a process's mailbox, or an error when it is not
/// alive.
pub fn message_queue_length(pid: Pid) -> Result(Int, Nil) {
  todo as "body in the build commit"
}

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
