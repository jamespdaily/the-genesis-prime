//// The runtime's own clock and counters, read by the read-only-data
//// benchmark.

import gleam/erlang/process.{type Pid}

/// The monotonic clock, in nanoseconds.
@external(erlang, "read_only_data_ffi", "monotonic_nanoseconds")
pub fn monotonic_nanoseconds() -> Int

/// Words a term takes on a process heap or in a persistent term, a sub-term
/// used twice counted once. The data of a binary over 64 bytes is not counted,
/// only the reference to it.
@external(erlang, "erts_debug", "size")
pub fn heap_words(term: anything) -> Int

/// The bytes of one machine word.
@external(erlang, "read_only_data_ffi", "word_bytes")
pub fn word_bytes() -> Int

/// The number of schedulers online.
@external(erlang, "read_only_data_ffi", "schedulers_online")
pub fn schedulers_online() -> Int

/// Garbage collects a process, so what it holds afterwards is only what it
/// still uses, and waits until it has.
@external(erlang, "read_only_data_ffi", "collect_process")
pub fn collect_process(pid: Pid) -> Nil

/// The bytes of memory a process holds: its heap, stack and message area.
@external(erlang, "read_only_data_ffi", "process_memory_bytes")
pub fn process_memory_bytes(pid: Pid) -> Int

/// The bytes of memory the runtime reports for off-heap binaries.
@external(erlang, "read_only_data_ffi", "binary_memory_bytes")
pub fn binary_memory_bytes() -> Int
