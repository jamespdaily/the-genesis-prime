//// How an asker reaches the process it asks. A rule's ask names a request;
//// the server's directory (genesis_prime/server) sends it to the process that
//// answers, a service (genesis_prime/service/shell) or a store worker
//// (genesis_prime/store/worker), and says where it went with `Sent`, so the
//// asker's shell knows what to watch and what to do at the deadline
//// (genesis_prime/connection/shell). The `Call` is what reaches a service.
////
//// A rule also names processes by `Address`, to watch them and to send them a
//// message without waiting. The server makes `Locate` and `Reach` once from
//// the names it started its processes with, and its shells use them, so no
//// rule holds a process id.

import genesis_prime/step.{type Address}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Subject}

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
  case process.named(name) {
    Error(Nil) -> Error(Nil)
    Ok(pid) -> {
      // The wire format of a named subject, sent to the pid found: a service
      // that ends after the lookup drops the message, where a send by name
      // would crash the asker.
      let _sent = send_to(pid, #(name, Call(message:, reply:)))
      Ok(ToService(pid:))
    }
  }
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
  todo as "built in the build"
}

@external(erlang, "erlang", "send")
fn send_to(
  pid: Pid,
  message: #(Name(Call(message, answer)), Call(message, answer)),
) -> Dynamic
