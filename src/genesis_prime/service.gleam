//// How an asker reaches the process it asks. A rule's ask names a request;
//// the server's directory (genesis_prime/server) sends it to the process that
//// answers, a service (genesis_prime/service/shell) by its name or, for a
//// map, by the subject its start returned (genesis_prime/world_map/registry), or
//// a store worker (genesis_prime/store/worker), and says where it went with
//// `Sent`, so the asker's shell knows what to watch and what to do at the
//// deadline (genesis_prime/connection/shell). The `Call` is what reaches a
//// service.
////
//// A rule also names processes by `Address`, to watch them and to send them a
//// message without waiting. The server makes `Locate` and `Reach` once from
//// the names it started its processes with, and its shells use them, so no
//// rule holds a process id.

import genesis_prime/step.{type Address, type CreatureStart}
import genesis_prime/step/runtime
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// What reaches a service when another process asks it or tells it: the
/// message, and for an ask how to answer it. `reply` sends the answer to the
/// asker, tagged with the ask, and never fails, so an answer to an asker that
/// has gone is dropped. A tell has no reply and gets none. It holds a function,
/// so it is a shell's type, never a rule's.
pub type Call(message, answer) {
  Call(message: message, reply: fn(answer) -> Nil)
  TellCall(message: message)
}

/// Where an asker's request went, so the asker knows what to watch and what
/// to do at the deadline.
pub type Sent {
  /// To a long-lived service. At the deadline it is left running, and its
  /// answer may come late.
  ToService(pid: Pid)
  /// To a worker started for this ask alone. At the deadline the asker ends
  /// it, so no work goes on for an asker that gave up, and no answer comes
  /// late.
  ToWorker(pid: Pid)
  /// Nothing was sent: the lookup that finds the process to ask got no reply
  /// by the ask's deadline, so whether the process runs is not known. The
  /// asker's shell gives its rule `NoAnswerInTime` at once, never
  /// `NotRunning`, which says the process is not there.
  NoReplyInTime
}

/// Ends the worker an ask went to, so no work goes on for an asker that gave
/// up; a service is left running.
pub fn end_worker(sent: Sent) -> Nil {
  case sent {
    ToWorker(pid:) -> process.send_abnormal_exit(pid, runtime.Shutdown)
    ToService(..) | NoReplyInTime -> Nil
  }
}

/// How a shell finds the process an address names, to watch it: its pid, or
/// `Error(Nil)` when no process is running there. Made once at start by the
/// server; a rule never sees it.
pub type Locate =
  fn(Address) -> Result(Pid, Nil)

/// How a service's shell reaches the processes its rule names by address.
/// Made once at start by the server, from the processes' names.
pub type Reach(outgoing) {
  Reach(
    /// Where an address runs, for `Watch`.
    locate: Locate,
    /// Sends the process at the address the message, in the form that
    /// process takes (a connection takes it as a `Woken` input), for `Send`.
    /// `Error(Nil)` when no process is running there; the message is
    /// dropped.
    send: fn(Address, outgoing) -> Result(Nil, Nil),
    /// Starts the creature a rule's `StartCreature` names and returns once it
    /// is running and found by its `Creature` address, or says why it did not
    /// start, as the creature supervisor reported it.
    start_creature: fn(CreatureStart) -> Result(Nil, StartChildError),
  )
}

/// A reach for a service that only watches: every send finds no process, so
/// the message is dropped, and no creature starts.
pub fn watch_only(locate locate: Locate) -> Reach(outgoing) {
  Reach(
    locate:,
    send: fn(_to, _message) { Error(Nil) },
    start_creature: fn(_creature) { Error(SupervisorNotRunning) },
  )
}

/// Sends a service the message, for an asker's directory: `Error(Nil)` when
/// no process holds the name, else `ToService` with the pid the asker
/// monitors.
pub fn call(
  name name: Name(Call(message, answer)),
  message message: message,
  reply reply: fn(answer) -> Nil,
) -> Result(Sent, Nil) {
  send_by_name(name:, message: Call(message:, reply:))
  |> result.map(ToService)
}

/// Sends a service the message through the subject its start returned, for
/// an asker's directory: `ToService` with the subject's owner, which the
/// asker monitors. A service that has ended drops the message, and the
/// asker's monitor gives `EndedBeforeAnswer`.
pub fn call_subject(
  subject subject: Subject(Call(message, answer)),
  message message: message,
  reply reply: fn(answer) -> Nil,
) -> Result(Sent, Nil) {
  use pid <- result.map(process.subject_owner(subject))
  process.send(subject, Call(message:, reply:))
  ToService(pid:)
}

/// Tells a service the message through the subject its start returned, for a
/// telling asker's directory: `ToService` with the subject's owner, and no reply
/// asked. A service that has ended drops the message.
pub fn tell_subject(
  subject subject: Subject(Call(message, answer)),
  message message: message,
) -> Result(Sent, Nil) {
  use pid <- result.map(process.subject_owner(subject))
  process.send(subject, TellCall(message:))
  ToService(pid:)
}

/// Sends the process registered under the name the message, in the form a
/// subject of that name receives it, and gives its pid: `Error(Nil)` when no
/// process holds the name. A process that ends after the lookup drops the
/// message, where a send by the name's subject would crash the sender.
pub fn send_by_name(
  name name: Name(message),
  message message: message,
) -> Result(Pid, Nil) {
  use pid <- result.map(process.named(name))
  let _sent = send_to(pid, #(name, message))
  pid
}

/// A factory supervisor named `name` that starts a service with `start` for each
/// argument it is asked with (`start_child`), each child temporary, a permanent
/// child of the supervisor that holds it, and given `shutdown_ms` to stop. A
/// temporary child is never restarted, so the restart limit, stated for the
/// check that every supervisor states one, is never reached: whoever asked for the
/// child starts another when it must (a map's creatures, Maps' maps).
pub fn temporary_factory(
  name name: Name(factory_supervisor.Message(argument, data)),
  shutdown_ms shutdown_ms: Int,
  start start: fn(argument) -> actor.StartResult(data),
) -> ChildSpecification(factory_supervisor.Supervisor(argument, data)) {
  factory_supervisor.worker_child(start)
  |> factory_supervisor.named(name)
  |> factory_supervisor.restart_strategy(supervision.Temporary)
  |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
  |> factory_supervisor.timeout(ms: shutdown_ms)
  |> factory_supervisor.supervised
  |> supervision.restart(supervision.Permanent)
}

/// Why a child of a factory supervisor was not started.
pub type StartChildError {
  /// No process holds the supervisor's name, or it ended while the call
  /// waited.
  SupervisorNotRunning
  /// The supervisor is running and the child's start failed, as the start
  /// reported it.
  ChildNotStarted(reason: actor.StartError)
}

/// Starts a child of the named factory supervisor, or says why it did not
/// start.
pub fn start_child(
  supervisor name: Name(factory_supervisor.Message(argument, data)),
  argument argument: argument,
) -> Result(actor.Started(data), StartChildError) {
  case
    unless_supervisor_not_running(fn() {
      factory_supervisor.start_child(
        factory_supervisor.get_by_name(name),
        argument,
      )
    })
  {
    Ok(Ok(started)) -> Ok(started)
    Ok(Error(reason)) -> Error(ChildNotStarted(reason:))
    Error(Nil) -> Error(SupervisorNotRunning)
  }
}

/// Logs why a child was not started, as a warning, for a caller that goes on
/// without it. A supervisor that is not running is not logged: it is stopping
/// or restarting, which its own log lines say.
pub fn warn_unless_not_running(error: StartChildError) -> Nil {
  case error {
    SupervisorNotRunning -> Nil
    ChildNotStarted(reason:) ->
      runtime.log(
        step.LogWarning,
        "the child " <> runtime.describe_start_error(reason),
        step.no_one,
      )
  }
}

/// A sentence that says why a child was not started, for the log line of a rule
/// that is told its creature did not start.
pub fn describe_start_child_error(error: StartChildError) -> String {
  case error {
    SupervisorNotRunning -> "the supervisor is not running"
    ChildNotStarted(reason:) -> runtime.describe_start_error(reason)
  }
}

/// The worker a started child is, as the `Sent` its asker monitors and ends at
/// its deadline; `Error(Nil)` for a child that did not start, whose reason is
/// logged (`warn_unless_not_running`).
pub fn sent_to_worker(
  started: Result(actor.Started(data), StartChildError),
) -> Result(Sent, Nil) {
  case started {
    Ok(started) -> Ok(ToWorker(pid: started.pid))
    Error(error) -> {
      warn_unless_not_running(error)
      Error(Nil)
    }
  }
}

/// OTP's `erlang:send/2`, which gives back the message it sent. The message is
/// the form a named subject receives, which `send_by_name`'s test pins.
@external(erlang, "erlang", "send")
fn send_to(
  pid: Pid,
  message: #(Name(message), message),
) -> #(Name(message), message)

/// Runs a function and turns the exits that say no supervisor is running into
/// an error: no process holds its name, or it ended with `shutdown` while the
/// call waited. Any other exit passes.
@external(erlang, "genesis_prime_service_ffi", "unless_supervisor_not_running")
fn unless_supervisor_not_running(run: fn() -> a) -> Result(a, Nil)
