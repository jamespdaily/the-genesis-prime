//// How an asker reaches the process it asks. A rule's ask names a request;
//// the server's directory (genesis_prime/server) sends it to the process that
//// answers, a service (genesis_prime/service/shell) or a store worker
//// (genesis_prime/store/worker), and says where it went with `Sent`, so the
//// asker's shell knows what to watch and what to do at the deadline
//// (genesis_prime/connection/shell). The `Call` is what reaches a service.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid}

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

@external(erlang, "erlang", "send")
fn send_to(
  pid: Pid,
  message: #(Name(Call(message, answer)), Call(message, answer)),
) -> Dynamic
