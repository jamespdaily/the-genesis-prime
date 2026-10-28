//// How an asker reaches the process it asks. A rule's ask names a request;
//// the server's directory (genesis_prime/server) sends it to the process that
//// answers, a service (genesis_prime/service/shell) by its name or, for a
//// map, by the subject its start returned (genesis_prime/world_map/maps), or
//// a store worker (genesis_prime/store/worker), and says where it went with
//// `Sent`, so the asker's shell knows what to watch and what to do at the
//// deadline (genesis_prime/connection/shell). The `Call` is what reaches a
//// service.
////
//// A rule also names processes by `Address`, to watch them and to send them a
//// message without waiting. The server makes `Locate` and `Reach` once from
//// the names it started its processes with, and its shells use them, so no
//// rule holds a process id.

import genesis_prime/step.{type Address}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/result

/// What reaches a service when another process asks it: the message, and
/// how to answer it. `reply` sends the answer to the asker, tagged with the
/// ask, and never fails, so an answer to an asker that has gone is dropped.
/// It holds a function, so it is a shell's type, never a rule's.
pub type Call(message, answer) {
  Call(message: message, reply: fn(answer) -> Nil)
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
}

/// How a shell finds the process an address names, to watch it: its pid, or
/// `Error(Nil)` when no process is running there, or the address names no
/// process yet (a map). Made once at start by the server; a rule never sees
/// it.
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

/// Starts a child of the named factory supervisor: `Error(Nil)` when the
/// supervisor is not running or the child does not start.
pub fn start_child(
  supervisor name: Name(factory_supervisor.Message(argument, data)),
  argument argument: argument,
) -> Result(actor.Started(data), Nil) {
  case
    unless_supervisor_not_running(fn() {
      factory_supervisor.start_child(
        factory_supervisor.get_by_name(name),
        argument,
      )
    })
  {
    Ok(Ok(started)) -> Ok(started)
    Ok(Error(_)) | Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "erlang", "send")
fn send_to(pid: Pid, message: #(Name(message), message)) -> Dynamic

/// Runs a function and turns the one exit that says no process holds a
/// supervisor's name into an error; any other exit passes.
@external(erlang, "service_ffi", "unless_supervisor_not_running")
fn unless_supervisor_not_running(run: fn() -> a) -> Result(a, Nil)
