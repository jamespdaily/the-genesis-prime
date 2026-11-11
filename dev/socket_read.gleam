//// How long a scripted client's read of a socket may wait for the server. A
//// test's read has no limit of its own: it goes on until the server writes or
//// the connection ends, and the test's deadline warns, names the read still open
//// and the read goes on (`open_wait`, `owned_test.run`). A load client has no test around it, so its
//// read carries a bound, and a server that does not answer within it stops the
//// client with the reason.

import mug
import open_wait

/// How a read waits: without a limit of its own, or for at most `wait_ms`.
pub type Limit {
  Open
  Within(wait_ms: Int)
}

/// How long one look at the socket lasts before an open wait looks again, in
/// milliseconds. It is no limit: an open wait goes on until the server writes
/// or the connection ends.
pub const look_ms = 1000

/// Receives the next bytes the server writes. An open read is named for the
/// test that owns the calling process (`open_wait`); a read with a bound gives
/// `Error(mug.Timeout)` when the server writes nothing within it.
pub fn receive(
  socket socket: mug.Socket,
  limit limit: Limit,
  what what: String,
) -> Result(BitArray, mug.Error) {
  case limit {
    Open -> open_wait.named(what, fn() { looking(socket) })
    Within(wait_ms:) -> mug.receive(socket, timeout_milliseconds: wait_ms)
  }
}

/// Receives the next bytes the server writes, looking at the socket again after
/// each `look_ms` until it writes or the connection ends.
pub fn looking(socket: mug.Socket) -> Result(BitArray, mug.Error) {
  case mug.receive(socket, timeout_milliseconds: look_ms) {
    Error(mug.Timeout) -> looking(socket)
    received -> received
  }
}

/// Receives exactly `byte_size` bytes the server writes, with no limit of its
/// own, and names the wait for the test that owns the calling process
/// (`open_wait`). It looks at the socket again after each `look_ms`, and the
/// bytes that came in the look before stay in the socket. It is the sibling of
/// `receive` for a read of a known size.
pub fn receive_exactly(
  socket socket: mug.Socket,
  byte_size byte_size: Int,
  what what: String,
) -> Result(BitArray, mug.Error) {
  open_wait.named(what, fn() { looking_for(socket, byte_size) })
}

fn looking_for(
  socket: mug.Socket,
  byte_size: Int,
) -> Result(BitArray, mug.Error) {
  case mug.receive_exact(socket, byte_size:, timeout_milliseconds: look_ms) {
    Error(mug.Timeout) -> looking_for(socket, byte_size)
    received -> received
  }
}
