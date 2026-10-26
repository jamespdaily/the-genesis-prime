//// Sending to a process by the name it is registered under, from a process
//// that must not crash when the name has no process. `process.send` to a
//// named subject looks the name up and asserts a process is registered, so a
//// process that ends between a caller's check and its send crashes the
//// caller. `erlang:send/2` to a name raises `badarg` for a name with no
//// process (OTP reference manual, `erlang:send/2`), which the external catches,
//// so a request that finds no process is a request nobody answers, which its
//// asker's deadline already handles. The message goes out at once from the
//// sender, so messages from one process arrive in the order they were sent
//// (OTP reference manual, "Processes", signal ordering), which a timer of 0
//// ms does not give: the timers of a node sit on the wheels of its schedulers,
//// and two timers of one process can fire in either order.

import gleam/erlang/process.{type Name, type Subject}

/// Sends the message to the process the subject reaches. It never crashes the
/// caller: a named subject whose name has no process drops the message.
pub fn send(
  subject subject: Subject(message),
  message message: message,
) -> Nil {
  case process.subject_name(subject) {
    Ok(name) -> send_to_name(name:, message:)
    Error(Nil) -> process.send(subject, message)
  }
}

/// Sends the message to the process registered under the name, as a named
/// subject receives it, and drops it when there is none. A runtime call Gleam
/// has no binding for: gleam_erlang's `process.send` crashes for a name with no
/// process, and its `send_after` goes through a timer.
@external(erlang, "named_send_ffi", "send")
fn send_to_name(name name: Name(message), message message: message) -> Nil
