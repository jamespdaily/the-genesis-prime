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

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision

/// What the coordinator and the processes that register with it share, made
/// once by whoever starts the tree. `name` is the coordinator's name, which
/// outlives its restarts. `drain_deadline_ms` is how long the listeners have to
/// stop accepting and the connections to close once told to, and
/// `flush_deadline_ms` how long the saving workers have to flush. `finished`
/// receives the outcome once the order has run.
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
  /// A process that holds state that is unsaved. `flush` saves it and returns
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
  Down(process.Down)
}

/// The settings of a tree: a coordinator name and a subject for the outcome,
/// made here, with the given deadlines. The subject belongs to the process that
/// calls this, which is the one that receives the outcome.
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

/// How long `register` waits for the coordinator to answer, in milliseconds.
const register_timeout_ms = 5000

/// What the coordinator knows: its settings, each process that registered with
/// the monitor the coordinator holds on it, and whether the order has run, after
/// which a second ask does nothing.
type State {
  State(settings: Settings, registered: List(Registered), status: Status)
}

type Status {
  Running
  Ordered
}

type Registered {
  Registered(process: Pid, monitor: Monitor, participant: Participant)
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
  actor.new_with_initialiser(1000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> process.select_monitors(Down)
    Ok(
      actor.initialised(State(settings:, registered: [], status: Running))
      |> actor.selecting(selector)
      |> actor.returning(subject),
    )
  })
  |> actor.named(settings.name)
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Register(process:, participant:, registered:) -> {
      let monitor = process.monitor(process)
      process.send(registered, Nil)
      actor.continue(
        State(..state, registered: [
          Registered(process:, monitor:, participant:),
          ..state.registered
        ]),
      )
    }
    Down(process.ProcessDown(monitor:, ..)) ->
      actor.continue(
        State(
          ..state,
          registered: list.filter(state.registered, fn(registered) {
            registered.monitor != monitor
          }),
        ),
      )
    Down(process.PortDown(..)) -> actor.continue(state)
    Stop ->
      case state.status {
        Ordered -> actor.continue(state)
        Running -> {
          process.send(state.settings.finished, run_order(state))
          actor.continue(State(..state, status: Ordered))
        }
      }
  }
}

/// Registers the calling process as taking part in the stop, and returns once
/// the coordinator has it. Crashes the caller when the coordinator does not
/// answer within 5 seconds: a process that could not be stopped in order must
/// not run.
pub fn register(
  settings settings: Settings,
  participant participant: Participant,
) -> Nil {
  actor.call(
    process.named_subject(settings.name),
    waiting: register_timeout_ms,
    sending: fn(registered) {
      Register(process: process.self(), participant:, registered:)
    },
  )
}

/// Asks the coordinator to run the order. A second ask while the order runs
/// or after it has run does nothing.
pub fn stop(settings: Settings) -> Nil {
  process.send(process.named_subject(settings.name), Stop)
}

/// The status a node ends with for an outcome: 0 for a clean stop, 1 when any
/// step failed.
pub fn exit_status(outcome: Outcome) -> Int {
  case outcome {
    Stopped(failures: []) -> 0
    Stopped(failures: [_, ..]) -> 1
  }
}

/// What the node does for the rest of its life, called by the process that
/// started the tree: makes SIGTERM ask for the order, logs that the server is
/// running, waits for the outcome, stops the tree, and ends the node with the
/// outcome's status. It does not return.
pub fn run(tree tree: Pid, settings settings: Settings) -> Nil {
  handle_sigterm(fn() { stop_or_end_node(settings) })
  log_info("the server is running; SIGTERM stops it in order")
  let outcome = process.receive_forever(settings.finished)
  stop_tree(tree)
  log_info("the server stopped")
  end_node(exit_status(outcome))
  process.sleep_forever()
}

/// Asks for the order. A SIGTERM that finds no coordinator, which a restart of
/// the coordinator leaves for a moment, ends the node without the order, with
/// status 1, and says so.
fn stop_or_end_node(settings: Settings) -> Nil {
  case process.named(settings.name) {
    Ok(_) -> stop(settings)
    Error(Nil) -> {
      log_error(
        "SIGTERM arrived while the shutdown coordinator was not running; the node ends without the ordered stop",
      )
      end_node(1)
    }
  }
}

/// Stops the top supervisor as its parent does, which stops its children in
/// the order opposite to their start, and waits until it has ended.
fn stop_tree(tree: Pid) -> Nil {
  let monitor = process.monitor(tree)
  process.send_exit(tree)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_down) { Nil })
  |> process.selector_receive_forever
}

/// Runs the order on what is registered: the listeners stop accepting, the
/// connections are told to close and are waited for, then the saving workers
/// flush. Each step's failure is logged and the order goes on.
fn run_order(state: State) -> Outcome {
  let settings = state.settings
  log_info("stopping: listeners, then connections, then saves")
  let listeners = list.filter_map(state.registered, as_listener)
  let connections = list.filter(state.registered, is_connection)
  let savers = list.filter_map(state.registered, as_saver)
  let listener_failures =
    stop_accepting(listeners, within: settings.drain_deadline_ms)
  drain(connections, within: settings.drain_deadline_ms)
  let flush_failures = flush(savers, within: settings.flush_deadline_ms)
  Stopped(failures: list.append(listener_failures, flush_failures))
}

fn as_listener(registered: Registered) -> Result(#(String, fn() -> Nil), Nil) {
  case registered.participant {
    Listener(name:, stop_accepting:) -> Ok(#(name, stop_accepting))
    Connection(..) | SavingWorker(..) -> Error(Nil)
  }
}

fn is_connection(registered: Registered) -> Bool {
  case registered.participant {
    Connection(..) -> True
    Listener(..) | SavingWorker(..) -> False
  }
}

fn as_saver(
  registered: Registered,
) -> Result(#(String, fn() -> Result(Nil, NotFlushed)), Nil) {
  case registered.participant {
    SavingWorker(name:, flush:) -> Ok(#(name, flush))
    Listener(..) | Connection(..) -> Error(Nil)
  }
}

fn stop_accepting(
  listeners: List(#(String, fn() -> Nil)),
  within ms: Int,
) -> List(Failure) {
  let attempts =
    attempt_all(list.map(listeners, fn(listener) { listener.1 }), within: ms)
  list.zip(listeners, attempts)
  |> list.filter_map(fn(pair) {
    let #(#(name, _), attempt) = pair
    case attempt {
      Done(Nil) -> Error(Nil)
      Crashed | TimedOut -> {
        log_error(
          "the listener " <> name <> " did not stop accepting connections",
        )
        Ok(ListenerNotStopped(name:))
      }
    }
  })
}

/// Tells each connection to close, then waits until each registered process has
/// ended or `ms` have passed, and ends the ones that have not.
fn drain(connections: List(Registered), within ms: Int) -> Nil {
  list.each(connections, fn(connection) {
    case connection.participant {
      Connection(close:) -> {
        let _closing = process.spawn_unlinked(close)
        Nil
      }
      Listener(..) | SavingWorker(..) -> Nil
    }
  })
  case wait_until_ended(connections, within: ms) {
    [] -> Nil
    [_, ..] as open -> {
      list.each(open, fn(connection) { process.kill(connection.process) })
      log_warning(
        int.to_string(list.length(open))
        <> " connection(s) did not close within "
        <> int.to_string(ms)
        <> " ms and were ended",
      )
    }
  }
}

/// What a wait for registered processes to end receives.
type Ending {
  ProcessEnded(Monitor)
  DeadlineReached
}

/// The processes among `registered` that are still running when `ms` have
/// passed, none once all have ended.
fn wait_until_ended(
  registered: List(Registered),
  within ms: Int,
) -> List(Registered) {
  let deadline = process.new_subject()
  let timer = process.send_after(deadline, ms, DeadlineReached)
  let selector =
    list.fold(
      registered,
      process.new_selector() |> process.select(deadline),
      fn(selector, one) {
        process.select_specific_monitor(selector, one.monitor, fn(_down) {
          ProcessEnded(one.monitor)
        })
      },
    )
  let open = wait_loop(selector, registered)
  let _cancelled = process.cancel_timer(timer)
  open
}

fn wait_loop(
  selector: process.Selector(Ending),
  open: List(Registered),
) -> List(Registered) {
  case open {
    [] -> []
    [_, ..] ->
      case process.selector_receive_forever(selector) {
        DeadlineReached -> open
        ProcessEnded(monitor) ->
          wait_loop(
            selector,
            list.filter(open, fn(one) { one.monitor != monitor }),
          )
      }
  }
}

fn flush(
  savers: List(#(String, fn() -> Result(Nil, NotFlushed))),
  within ms: Int,
) -> List(Failure) {
  let attempts =
    attempt_all(list.map(savers, fn(saver) { saver.1 }), within: ms)
  list.zip(savers, attempts)
  |> list.filter_map(fn(pair) {
    let #(#(name, _), attempt) = pair
    case attempt {
      Done(Ok(Nil)) -> Error(Nil)
      Done(Error(NotFlushed(reason:))) -> {
        log_error("the saving worker " <> name <> " did not flush: " <> reason)
        Ok(FlushFailed(worker: name, reason:))
      }
      Crashed | TimedOut -> {
        log_error(
          "the saving worker "
          <> name
          <> " did not answer its flush within "
          <> int.to_string(ms)
          <> " ms or crashed",
        )
        Ok(FlushNotAnswered(worker: name))
      }
    }
  })
}

/// How a piece of work asked of another process ended.
type Attempt(a) {
  Done(a)
  Crashed
  TimedOut
}

/// What `attempt_all` receives about the pieces of work, by their place in the
/// list.
type Report(a) {
  Finished(index: Int, value: a)
  Died(index: Int)
  Late
}

/// Runs each piece of work in a process of its own, all at once, and gives how
/// each ended in the order of the work: its value, or that its process crashed,
/// or that it had not ended within `ms`, in which case it is ended.
fn attempt_all(works: List(fn() -> a), within ms: Int) -> List(Attempt(a)) {
  let finished = process.new_subject()
  let deadline = process.new_subject()
  let started =
    list.index_map(works, fn(work, index) {
      let pid =
        process.spawn_unlinked(fn() {
          process.send(finished, Finished(index, work()))
        })
      #(index, pid, process.monitor(pid))
    })
  let timer = process.send_after(deadline, ms, Late)
  let selector =
    list.fold(
      started,
      process.new_selector()
        |> process.select(finished)
        |> process.select(deadline),
      fn(selector, one) {
        let #(index, _pid, monitor) = one
        process.select_specific_monitor(selector, monitor, fn(_down) {
          Died(index)
        })
      },
    )
  let reached =
    collect(selector:, remaining: list.length(works), found: dict.new())
  let _cancelled = process.cancel_timer(timer)
  list.each(started, fn(one) {
    let #(_index, pid, monitor) = one
    process.demonitor_process(monitor)
    process.kill(pid)
  })
  list.index_map(works, fn(_work, index) {
    case dict.get(reached, index) {
      Ok(attempt) -> attempt
      Error(Nil) -> TimedOut
    }
  })
}

fn collect(
  selector selector: process.Selector(Report(a)),
  remaining remaining: Int,
  found found: Dict(Int, Attempt(a)),
) -> Dict(Int, Attempt(a)) {
  case remaining {
    0 -> found
    _ ->
      case process.selector_receive_forever(selector) {
        Finished(index:, value:) ->
          collect(
            selector:,
            remaining: remaining - 1,
            found: dict.insert(found, index, Done(value)),
          )
        Died(index:) ->
          case dict.has_key(found, index) {
            True -> collect(selector:, remaining:, found:)
            False ->
              collect(
                selector:,
                remaining: remaining - 1,
                found: dict.insert(found, index, Crashed),
              )
          }
        Late -> found
      }
  }
}

/// Makes SIGTERM call `on_sigterm`, in place of the VM's own handler that stops
/// the node with `init:stop()`. It runs in the VM's signal server, so it only
/// sends a message.
@external(erlang, "shutdown_ffi", "handle_sigterm")
fn handle_sigterm(on_sigterm: fn() -> Nil) -> Nil

@external(erlang, "shutdown_ffi", "log_info")
fn log_info(text: String) -> Nil

@external(erlang, "shutdown_ffi", "log_warning")
fn log_warning(text: String) -> Nil

@external(erlang, "shutdown_ffi", "log_error")
fn log_error(text: String) -> Nil

/// Ends the node with the status once the VM has stopped its applications.
@external(erlang, "shutdown_ffi", "end_node")
fn end_node(status: Int) -> Nil
