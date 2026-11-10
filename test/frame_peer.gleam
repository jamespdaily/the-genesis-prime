//// A TCP peer that writes the bytes a test hands it in one send, so a test can
//// make a single socket read hold several messages, which a real server only
//// does when its writes happen to reach the client together. Erlang's `gen_tcp`
//// is used because the project's socket package, mug, only connects.

import mug

/// The peer's listening socket.
pub type Listener

/// Listens on a free loopback port, owned by the calling process, and gives the
/// socket and the port.
@external(erlang, "frame_peer_ffi", "listen")
pub fn listen() -> #(Listener, Int)

/// Accepts one connection on `listener` and writes `bytes` to it in a single
/// send, in a process linked to the caller; the connection stays open until the
/// caller ends.
@external(erlang, "frame_peer_ffi", "write_once_accepted")
pub fn write_once_accepted(listener: Listener, bytes: BitArray) -> Nil

/// A connection the peer accepted, which the caller writes to as it chooses.
pub type Connection

/// Accepts the one connection a client has made to `listener` (its connect has
/// returned, so it waits in the listener's queue), owned by the calling process.
@external(erlang, "frame_peer_ffi", "accept")
pub fn accept(listener: Listener) -> Connection

/// Writes `bytes` to the connection in a single send. Any process may write.
@external(erlang, "frame_peer_ffi", "write")
pub fn write(connection: Connection, bytes: BitArray) -> Nil

/// How many bytes the client's socket has received from the peer since it
/// opened (the socket's own count, `inet:getstat` `recv_oct`): the bytes its
/// owner has taken from the system, not the bytes written to it.
@external(erlang, "frame_peer_ffi", "bytes_received")
pub fn bytes_received(client: mug.Socket) -> Int
