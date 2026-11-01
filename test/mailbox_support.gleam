//// Reads how many messages wait in a process's mailbox and which processes it
//// monitors, for the tests that show a process left none behind, that a call
//// is waiting in one, or that a process holds no monitor it should have
//// dropped.

import gleam/erlang/process.{type Pid}

/// The number of messages waiting in the process's mailbox.
@external(erlang, "mailbox_support_ffi", "queued")
pub fn queued(pid: Pid) -> Int

/// The processes the process holds a monitor on, one entry for each monitor.
@external(erlang, "mailbox_support_ffi", "monitored")
pub fn monitored(pid: Pid) -> List(Pid)
