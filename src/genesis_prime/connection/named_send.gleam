//// Sending to a process by the name it is registered under, from a process
//// that must not crash when the name has no process. `process.send` to a
//// named subject looks the name up and asserts a process is registered, so a
//// process that ends between a caller's check and its send crashes the
//// caller. `erlang:send_after/3` with a delay of 0 looks the name up when the
//// message is delivered and gives no error when no process has the name (OTP
//// reference manual, `erlang:send_after/3`: "No error is returned if the name
//// does not refer to a process"), so a request sent this way that finds no
//// process is a request nobody answers, which its asker's deadline already
//// handles.

import gleam/erlang/process.{type Subject}

/// Sends the message to the process the subject reaches. It never crashes the
/// caller: a named subject whose name has no process drops the message.
pub fn send(
  subject subject: Subject(message),
  message message: message,
) -> Nil {
  process.send_after(subject, 0, message)
  Nil
}
