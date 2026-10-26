//// The ordered stop of the server: stop accepting, drain connections, flush
//// saves, then stop the tree and the node.
////
//// A process that takes part registers itself with `register` as it starts,
//// naming what it is by a `Participant`, and the coordinator (a child of the
//// top supervisor, started with `supervised`) runs the participants in order
//// when a stop is asked for, which is what a SIGTERM does once `run` has
//// installed its handler. A child the top supervisor restarts is not stopped:
//// only `stop` runs the order.
////
//// How the processes of the game plug in:
//// - a listener (the socket owner) registers `Listener` from its initialiser;
//// - each connection registers `Connection` from its initialiser;
//// - each process that saves state registers `SavingWorker` from its
////   initialiser.
//// Each is handed `Settings` as a start argument, and its closures send its
//// own messages, so the module that owns a process keeps the messages that
//// process understands. A registration lasts as long as the registering
//// process: the coordinator monitors it and forgets it when it ends, so a
//// restarted process registers again.

import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/supervision

/// What the coordinator and the processes that register with it share, made
/// once by whoever starts the tree. `name` is the coordinator's name, which
/// outlives its restarts. `drain_deadline_ms` is how long connections have to
/// close once told to, and `flush_deadline_ms` how long the saving workers
/// have to flush. `finished` receives the outcome once the order has run.
pub type Settings {
  Settings(
    name: Name(Message),
    drain_deadline_ms: Int,
    flush_deadline_ms: Int,
    finished: Subject(Outcome),
  )
}

/// What a process that takes part in the stop is, and what the coordinator may
/// ask of it. Each closure runs in a process of the coordinator's making, never
/// in the coordinator, and is given a deadline.
pub type Participant {
  /// A process that accepts connections. `stop_accepting` returns once it
  /// refuses new ones.
  Listener(name: String, stop_accepting: fn() -> Nil)
  /// A process that owns one connection. `close` asks it to close, and returns
  /// at once; the coordinator waits for the registering process to end.
  Connection(close: fn() -> Nil)
  /// A process that holds state not yet saved. `flush` saves it and returns
  /// once it is saved.
  SavingWorker(name: String, flush: fn() -> Result(Nil, NotFlushed))
}

/// Why a saving worker could not save what it holds, for the log line and the
/// outcome.
pub type NotFlushed {
  NotFlushed(reason: String)
}

/// A step of the order that did not do what it was asked.
pub type Failure {
  /// A listener did not report, within the deadline, that it refuses new
  /// connections.
  ListenerNotStopped(name: String)
  /// A saving worker answered that it could not save.
  FlushFailed(worker: String, reason: String)
  /// A saving worker did not answer within the deadline, or crashed.
  FlushNotAnswered(worker: String)
}

/// How the order ended. An empty list is a clean stop.
pub type Outcome {
  Stopped(failures: List(Failure))
}

/// What the coordinator receives.
pub opaque type Message {
  Register(process: Pid, participant: Participant, registered: Subject(Nil))
  Stop
  Ended(process.Down)
}

/// The settings of a tree: a coordinator name and a subject for the outcome,
/// made here, with the given deadlines.
pub fn new(
  drain_deadline_ms drain_deadline_ms: Int,
  flush_deadline_ms flush_deadline_ms: Int,
) -> Settings {
  Settings(
    name: process.new_name("shutdown"),
    drain_deadline_ms:,
    flush_deadline_ms:,
    finished: process.new_subject(),
  )
}

/// The coordinator as a child of the top supervisor. It holds the
/// registrations in memory, so a restart empties them and the processes that
/// registered before it must register again.
pub fn supervised(
  settings: Settings,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(settings) })
  |> supervision.timeout(ms: 1000)
}

fn start(
  settings: Settings,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  panic as "the coordinator is not built yet"
}

/// Registers the calling process as taking part in the stop, and returns once
/// the coordinator has it. Crashes the caller when the coordinator does not
/// answer within 5 seconds: a process that could not be stopped in order must
/// not run.
pub fn register(settings: Settings, participant: Participant) -> Nil {
  panic as "register is not built yet"
}

/// Asks the coordinator to run the order. A second ask while the order runs
/// or after it has run does nothing.
pub fn stop(settings: Settings) -> Nil {
  panic as "stop is not built yet"
}

/// The status a node ends with for an outcome: 0 for a clean stop, 1 when any
/// step failed.
pub fn exit_status(outcome: Outcome) -> Int {
  panic as "exit_status is not built yet"
}

/// What the node does for the rest of its life, called by the process that
/// started the tree: makes SIGTERM ask for the order, logs that the server is
/// running, waits for the outcome, stops the tree, and ends the node with the
/// outcome's status.
pub fn run(tree tree: Pid, settings settings: Settings) -> Nil {
  panic as "run is not built yet"
}
