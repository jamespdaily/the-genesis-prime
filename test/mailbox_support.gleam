//// Reads how many messages wait in a process's mailbox, for the tests that
//// show a process left none behind or that a call is waiting in one.

import gleam/erlang/process.{type Pid}

/// The number of messages waiting in the process's mailbox.
@external(erlang, "mailbox_support_ffi", "queued")
pub fn queued(pid: Pid) -> Int
