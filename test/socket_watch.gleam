//// Watches a socket owner's socket from outside: what the runtime sends the
//// owner and what waits in the owner's mailbox. A test waits on the
//// runtime's own events, the port's sends, never on time.

import gleam/erlang/process.{type Pid}

/// What the runtime sends a socket's owner.
pub type Sent {
  /// A read of bytes (`{tcp, Socket, Bytes}`).
  Read
  /// The reads asked for with `{active, N}` are all sent
  /// (`{tcp_passive, Socket}`).
  ReadsUsedUp
}

/// Makes the calling process the tracer of what the owner's socket sends the
/// owner. Fails when the process owns no socket.
@external(erlang, "socket_watch_ffi", "trace_reads")
pub fn trace_reads(owner: Pid) -> Result(Nil, Nil)

/// Waits until the traced socket has sent `count` more messages, and returns
/// them in the order sent; fails when `within_ms` passes without the next.
@external(erlang, "socket_watch_ffi", "await_reads")
pub fn await_reads(count: Int, within_ms: Int) -> Result(List(Sent), Nil)

/// The number of messages waiting in a process's mailbox.
@external(erlang, "socket_watch_ffi", "mailbox_length")
pub fn mailbox_length(pid: Pid) -> Int

/// The most bytes one read of the owner's socket holds (the socket's `buffer`
/// option).
@external(erlang, "socket_watch_ffi", "read_buffer_bytes")
pub fn read_buffer_bytes(owner: Pid) -> Int
