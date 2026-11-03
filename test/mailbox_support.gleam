//// Reads how many messages wait in a process's mailbox and which processes it
//// monitors, for the tests that show a process left none behind, that a call
//// is waiting in one, or that a process holds no monitor it should have
//// dropped.

import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid, type Subject}

/// The number of messages waiting in the process's mailbox.
@external(erlang, "mailbox_support_ffi", "queued")
pub fn queued(pid: Pid) -> Int

/// Every message waiting in the subject, in the order they came, taken out of
/// it. A message a process sent before a signal it sent afterwards, such as
/// its end, is waiting once that signal has come: Erlang orders signals per
/// sender.
pub fn drain(messages: Subject(message)) -> List(message) {
  case process.receive(messages, 0) {
    Ok(message) -> [message, ..drain(messages)]
    Error(Nil) -> []
  }
}

/// Whether a `gen_server` call made by `caller` is in the process's mailbox: a
/// call made to a process that takes none, because it is suspended or stopping
/// its children, stays there. It is the call's own message that is looked for,
/// so no other message makes it true, and a process that has ended has none.
/// Tests wait on it with `event_wait.until`.
@external(erlang, "mailbox_support_ffi", "call_waiting_from")
pub fn call_waiting_from(pid pid: Pid, caller caller: Pid) -> Bool

/// How many messages waiting in the process's mailbox are tuples whose first
/// element is the atom `tag`. A mailbox's length is no measure of what a
/// process has taken: one that writes to a socket holds the port's reply to its
/// write until it next runs (`{inet_reply, Port, ok, Ref}`), possibly after the
/// peer has read the bytes.
@external(erlang, "mailbox_support_ffi", "tagged")
pub fn tagged(pid: Pid, tag: Atom) -> Int

/// How many messages waiting in the process's mailbox reached it by a subject:
/// tuples whose first element is a reference, the subject's own tag.
@external(erlang, "mailbox_support_ffi", "tagged_by_reference")
pub fn tagged_by_reference(pid: Pid) -> Int

/// Sends the process a message that came through no subject, as any process
/// may send one to a pid it knows.
pub fn send_raw(to pid: Pid, message message: message) -> Nil {
  let _sent = send_term(pid, message)
  Nil
}

@external(erlang, "erlang", "send")
fn send_term(to: Pid, message: message) -> message

/// The messages waiting in the process's mailbox, as Erlang prints them.
@external(erlang, "mailbox_support_ffi", "waiting")
pub fn waiting(pid: Pid) -> String

/// The processes the process holds a monitor on, one entry for each monitor.
@external(erlang, "mailbox_support_ffi", "monitored")
pub fn monitored(pid: Pid) -> List(Pid)
