//// A TCP socket through OTP's `gen_tcp`, with a Gleam type for every value.
//// Every socket is in binary mode with no packet framing, because the frame
//// is cut by `frame.decode`, and every read reaches the process that owns the
//// socket as a message.
////
//// The helpers are in `genesis_prime_socket_ffi.erl`; this module is the only
//// one that names `gen_tcp`'s messages.

import gleam/erlang/process.{type Selector}

/// A socket that waits for connections.
pub type ListenSocket

/// A connected socket. The process that owns it receives its reads, and the
/// socket closes when that process ends.
pub type Socket

/// Why a socket call failed.
pub type Reason {
  /// The socket is closed.
  Closed
  /// A wait ran out.
  Timeout
  /// The port is already in use.
  AddressInUse
  /// The peer reset the connection.
  ConnectionReset
  /// Any other POSIX error, by its name.
  Other(posix: String)
}

/// How many reads the runtime hands a socket's owner before it asks for more.
/// This bounds what a slow owner holds: the owner's mailbox never holds more
/// reads than it asked for.
pub type FlowControl {
  /// One read, then the owner asks again (`{active, once}`).
  ActiveOnce
  /// `reads` reads, then the runtime sends `ReadsUsedUp` and the owner asks
  /// again (`{active, N}`).
  ActiveCount(reads: Int)
}

/// What a socket's owner is told.
pub type Event {
  /// A read of bytes.
  Received(bytes: BitArray)
  /// The peer closed the socket.
  PeerClosed
  /// The socket failed.
  Failed(reason: Reason)
  /// The reads asked for with `ActiveCount` have all arrived.
  ReadsUsedUp
}

/// Starts waiting for connections on `port`, on every address; port 0 takes a
/// free one.
@external(erlang, "genesis_prime_socket_ffi", "listen")
pub fn listen(port port: Int) -> Result(ListenSocket, Reason)

/// The port a listening socket waits on.
@external(erlang, "genesis_prime_socket_ffi", "listening_port")
pub fn listening_port(socket socket: ListenSocket) -> Result(Int, Reason)

/// Waits for the next connection. The calling process owns the new socket,
/// which sends it nothing until `arm` is called.
@external(erlang, "genesis_prime_socket_ffi", "accept")
pub fn accept(socket socket: ListenSocket) -> Result(Socket, Reason)

/// Makes the process the socket's owner.
@external(erlang, "genesis_prime_socket_ffi", "give_to")
pub fn give_to(
  socket socket: Socket,
  owner owner: process.Pid,
) -> Result(Nil, Reason)

/// Asks the runtime for reads in the given flow control.
@external(erlang, "genesis_prime_socket_ffi", "arm")
pub fn arm(
  socket socket: Socket,
  flow_control flow_control: FlowControl,
) -> Result(Nil, Reason)

/// Closes the socket.
@external(erlang, "genesis_prime_socket_ffi", "close")
pub fn close(socket socket: Socket) -> Nil

/// The peer's address and port as text, for the log, or `unknown` when the
/// socket is closed.
@external(erlang, "genesis_prime_socket_ffi", "peer")
pub fn peer(socket socket: Socket) -> String

/// Adds the socket's events to a selector, each mapped to a message.
pub fn select(
  selector selector: Selector(message),
  mapping mapping: fn(Event) -> message,
) -> Selector(message) {
  todo as "select gen_tcp's four messages"
}
