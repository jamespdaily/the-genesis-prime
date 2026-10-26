//// The server's always-on telemetry: a process that, at a set interval,
//// writes one info line whose metadata holds the runtime's numbers, so any
//// log reader sees them while the server runs. Nothing is opened for it: no
//// port, no remote shell, no exporter.
////
//// The line's `numbers` map holds, each from OTP's own counters:
//// - `memory_total_bytes`, `memory_processes_bytes`, `memory_binary_bytes`
////   and `memory_ets_bytes`, from `erlang:memory`;
//// - `process_count` and `port_count`;
//// - `run_queue_length`, the processes waiting for a scheduler;
//// - `scheduler_use`, a ratio between 0 and 1: the time the schedulers ran
////   processes over the time they existed, since the previous line, from
////   `scheduler_wall_time`;
//// - for each kind of busy process registered with `register`, called
////   `kind`, `<kind>_largest_queue` and `<kind>_largest_heap_words`: the
////   most messages waiting in one process's mailbox, and the most words one
////   process holds in its heap, stack and waiting messages
////   (`total_heap_size`), at the moment of the line.
////
//// A restart rebuilds the process from its settings, the start argument, and
//// forgets the kinds registered with it, so a process that registers a kind
//// registers it again when it starts.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// What the snapshot process starts with. `name` is the name it registers and
/// that a process finds it by to register a kind, made once by whoever starts
/// the tree, so two trees in one node never share it. `interval_milliseconds`
/// is the time between two lines.
pub type Settings {
  Settings(name: Name(Message), interval_milliseconds: Int)
}

/// A kind of busy process whose largest mailbox and heap each line reports.
/// `name` is the kind's own name, written by the registrant, never client
/// input. `processes` lists the live processes of the kind at the moment it
/// is called; the snapshot process calls it once for each line.
pub type Kind {
  Kind(name: String, processes: fn() -> List(Pid))
}

/// Every message the snapshot process receives: the timer for the next line
/// is due, a kind is registered, or something else arrived, which is logged
/// as a bug.
pub opaque type Message {
  Tick
  Register(kind: Kind)
  Unexpected(received: Dynamic)
}

/// The settings with the interval of 10 seconds, which is the interval of a
/// running server.
pub fn settings(name: Name(Message)) -> Settings {
  todo as "settings with the default interval"
}

/// Starts the snapshot process under `settings.name`. It enables the
/// runtime's scheduler time accounting, which the `scheduler_use` number
/// reads, and writes its first line one interval after it starts.
pub fn start(
  settings: Settings,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  todo as "start the snapshot process"
}

/// The snapshot process as a child of a supervisor: restarted whenever it
/// ends, and given one second to stop, as every worker that flushes no saves.
pub fn supervised(
  settings: Settings,
) -> supervision.ChildSpecification(Subject(Message)) {
  todo as "the snapshot process as a supervised worker with its shutdown time"
}

/// Registers a kind of busy process with the snapshot process named `name`,
/// so every line from the next on reports its largest mailbox and heap. A
/// kind registered under a name already registered replaces it.
pub fn register(snapshot name: Name(Message), kind kind: Kind) -> Nil {
  todo as "send the kind to the snapshot process"
}
