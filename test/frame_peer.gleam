//// A TCP peer that writes the bytes a test hands it in one send, so a test can
//// make a single socket read hold several messages, which a real server only
//// does when its writes happen to reach the client together. Erlang's `gen_tcp`
//// is used because the project's socket package, mug, only connects.

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
