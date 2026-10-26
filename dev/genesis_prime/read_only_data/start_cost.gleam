//// What it costs a process to start with a variant: the time from starting
//// the process until it has opened the loaded tables and says it is ready.
//// Persistent terms and ETS only look the tables up; owner state copies them
//// into the new process.

import genesis_prime/read_only_data/measurement
import genesis_prime/read_only_data/variant.{type Loaded}
import gleam/erlang/process

/// The nanoseconds from starting one process until it is ready to read, for
/// one start. It returns after the process has gone, so the next start does
/// not begin while this one's memory is freed.
pub fn time_to_ready(loaded: Loaded) -> Int {
  let ready = process.new_subject()
  let started = measurement.monotonic_nanoseconds()
  let pid =
    process.spawn_unlinked(fn() {
      let _reader = loaded.open_reader()
      process.send(ready, Nil)
    })
  let assert Ok(_ready) = process.receive(ready, 600_000)
    as "a process did not become ready in time"
  let elapsed = measurement.monotonic_nanoseconds() - started
  let monitor = process.monitor(pid)
  let assert Ok(_down) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 60_000)
    as "a process did not stop"
  elapsed
}
