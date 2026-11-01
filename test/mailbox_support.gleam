//// Reads how many messages wait in a process's mailbox and which processes it
//// monitors, for the tests that show a process left none behind, that a call
//// is waiting in one, or that a process holds no monitor it should have
//// dropped.

import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}

/// The number of messages waiting in the process's mailbox.
@external(erlang, "mailbox_support_ffi", "queued")
pub fn queued(pid: Pid) -> Int

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

/// The messages waiting in the process's mailbox, as Erlang prints them.
@external(erlang, "mailbox_support_ffi", "waiting")
pub fn waiting(pid: Pid) -> String

/// The processes the process holds a monitor on, one entry for each monitor.
@external(erlang, "mailbox_support_ffi", "monitored")
pub fn monitored(pid: Pid) -> List(Pid)
