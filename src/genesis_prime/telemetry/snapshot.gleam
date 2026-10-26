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
////
//// The runtime's counters are read through `src/snapshot_ffi.erl`, because
//// neither `gleam_erlang` nor `gleam_otp` binds `statistics`, `system_info`
//// or `process_info`; `erlang:memory` is bound directly.

import genesis_prime/telemetry/log
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision

/// The time between two lines when nothing else is chosen, in milliseconds.
const default_interval_milliseconds = 10_000

/// How long the snapshot process has to start, in milliseconds.
const start_deadline_milliseconds = 1000

/// How long the top supervisor waits for the snapshot process to stop before
/// it is killed, in milliseconds. The process saves nothing, so it takes the
/// same second as every worker that flushes no saves.
const shutdown_milliseconds = 1000

/// Who the snapshot process's own lines are from: the process, by its name.
const snapshot_who =
  log.Who(
    account: None,
    actor: None,
    place: Some(log.Process("snapshot")),
    message: None,
  )

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

/// The state of the snapshot process: its settings, its own subject, the
/// kinds registered with it by name, and the scheduler time at its previous
/// line (or at its start), which the next line's `scheduler_use` is measured
/// from.
type State {
  State(
    settings: Settings,
    self: Subject(Message),
    kinds: Dict(String, Kind),
    scheduler_time: SchedulerTime,
  )
}

/// The time the schedulers ran processes and the time they existed, summed
/// over the schedulers online, in the runtime's native time unit.
type SchedulerTime {
  SchedulerTime(busy: Int, total: Int)
}

/// The kinds of memory `erlang:memory` reports in bytes, each named by the
/// atom the runtime reads.
type MemoryKind {
  Total
  Processes
  Binary
  Ets
}

/// The settings with the default interval of 10 seconds.
pub fn settings(name: Name(Message)) -> Settings {
  Settings(name:, interval_milliseconds: default_interval_milliseconds)
}

/// Starts the snapshot process under `settings.name`. It enables the
/// runtime's scheduler time accounting, which the `scheduler_use` number
/// reads, and writes its first line one interval after it starts.
pub fn start(
  settings: Settings,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    enable_scheduler_wall_time()
    let state =
      State(
        settings:,
        self:,
        kinds: dict.new(),
        scheduler_time: scheduler_time(),
      )
    schedule_tick(state)
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_other(Unexpected)
    actor.initialised(state)
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(settings.name)
  |> actor.on_message(handle)
  |> actor.start
}

/// The snapshot process as a child of a supervisor: restarted whenever it
/// ends, and given one second to stop, as every worker that flushes no saves.
pub fn supervised(
  settings: Settings,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(settings) })
  |> supervision.timeout(ms: shutdown_milliseconds)
}

/// Registers a kind of busy process with the snapshot process named `name`,
/// so every line after the registration reports its largest mailbox and
/// heap. A kind registered under a name already registered replaces it.
pub fn register(snapshot name: Name(Message), kind kind: Kind) -> Nil {
  process.send(process.named_subject(name), Register(kind))
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Tick -> {
      let scheduler_time = scheduler_time()
      log.info_with_numbers(
        snapshot_who,
        "snapshot",
        numbers(state, scheduler_time),
      )
      let state = State(..state, scheduler_time:)
      schedule_tick(state)
      actor.continue(state)
    }
    Register(kind:) ->
      actor.continue(
        State(..state, kinds: dict.insert(state.kinds, kind.name, kind)),
      )
    Unexpected(..) -> {
      log.error(
        snapshot_who,
        "the snapshot process received a message it does not handle",
      )
      actor.continue(state)
    }
  }
}

fn schedule_tick(state: State) -> Nil {
  let _timer =
    process.send_after(state.self, state.settings.interval_milliseconds, Tick)
  Nil
}

/// Every number of one line, by the key it is written under.
fn numbers(
  state: State,
  scheduler_time: SchedulerTime,
) -> Dict(String, log.Number) {
  let scheduler_use =
    scheduler_use(since: state.scheduler_time, until: scheduler_time)
  dict.from_list([
    #("memory_total_bytes", log.Count(memory(Total))),
    #("memory_processes_bytes", log.Count(memory(Processes))),
    #("memory_binary_bytes", log.Count(memory(Binary))),
    #("memory_ets_bytes", log.Count(memory(Ets))),
    #("process_count", log.Count(process_count())),
    #("port_count", log.Count(port_count())),
    #("run_queue_length", log.Count(run_queue_length())),
    #("scheduler_use", log.Ratio(scheduler_use)),
  ])
  |> dict.merge(kind_numbers(state.kinds))
}

/// The time the schedulers ran processes over the time they existed between
/// two readings, from 0 to 1; 0 when no time passed between them.
fn scheduler_use(
  since since: SchedulerTime,
  until until: SchedulerTime,
) -> Float {
  let total = until.total - since.total
  case total > 0 {
    True ->
      float.clamp(
        int.to_float(until.busy - since.busy) /. int.to_float(total),
        min: 0.0,
        max: 1.0,
      )
    False -> 0.0
  }
}

/// For each registered kind, the largest mailbox and the largest heap among
/// the processes it lists at the moment of the call. A process that ended
/// since it was listed is left out.
fn kind_numbers(kinds: Dict(String, Kind)) -> Dict(String, log.Number) {
  dict.values(kinds)
  |> list.flat_map(fn(kind) {
    let readings = list.filter_map(kind.processes(), heap_and_queue)
    [
      #(
        kind.name <> "_largest_queue",
        log.Count(largest(list.map(readings, fn(reading) { reading.1 }))),
      ),
      #(
        kind.name <> "_largest_heap_words",
        log.Count(largest(list.map(readings, fn(reading) { reading.0 }))),
      ),
    ]
  })
  |> dict.from_list
}

fn largest(values: List(Int)) -> Int {
  list.fold(values, 0, int.max)
}

fn scheduler_time() -> SchedulerTime {
  let #(busy, total) = scheduler_times()
  SchedulerTime(busy:, total:)
}

@external(erlang, "erlang", "memory")
fn memory(kind: MemoryKind) -> Int

@external(erlang, "snapshot_ffi", "enable_scheduler_wall_time")
fn enable_scheduler_wall_time() -> Nil

@external(erlang, "snapshot_ffi", "scheduler_times")
fn scheduler_times() -> #(Int, Int)

@external(erlang, "snapshot_ffi", "process_count")
fn process_count() -> Int

@external(erlang, "snapshot_ffi", "port_count")
fn port_count() -> Int

@external(erlang, "snapshot_ffi", "run_queue_length")
fn run_queue_length() -> Int

@external(erlang, "snapshot_ffi", "heap_and_queue")
fn heap_and_queue(pid: Pid) -> Result(#(Int, Int), Nil)
