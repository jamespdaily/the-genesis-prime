//// Reads how many messages wait in a process's mailbox, for the tests of a
//// process that writes to no socket: a socket's owner holds the port's reply
//// to its own write until it next runs, so its mailbox length is no measure of
//// what it has taken (`mailbox_support.tagged` counts one kind of message).

import gleam/erlang/process.{type Pid}

/// The number of messages waiting in a process's mailbox.
@external(erlang, "socket_watch_ffi", "mailbox_length")
pub fn mailbox_length(pid: Pid) -> Int
