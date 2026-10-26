//// A TCP socket through OTP's `gen_tcp`, with a Gleam type for every value.
//// Every socket is in binary mode with no packet framing, because the frame
//// is cut by `frame.decode`, and every read reaches the process that owns the
//// socket as a message.
////
//// The helpers are in `genesis_prime_socket_ffi.erl`; this module is the only
//// one that names `gen_tcp`'s messages.

import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type Selector}
import gleam/option.{type Option}

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
  /// A read of bytes, at most the socket's `buffer` option.
  Received(bytes: BitArray)
  /// The peer closed the socket.
  PeerClosed
  /// The socket failed.
  Failed(reason: Reason)
  /// The reads asked for with `ActiveCount` have all arrived.
  ReadsUsedUp
}

/// The reason in words, for the log.
pub fn describe(reason reason: Reason) -> String {
  case reason {
    Closed -> "closed"
    Timeout -> "timed out"
    AddressInUse -> "address in use"
    ConnectionReset -> "reset by the client"
    Other(posix:) -> posix
  }
}

/// The first element of one of `gen_tcp`'s messages.
type Tag

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
pub fn arm(
  socket socket: Socket,
  flow_control flow_control: FlowControl,
) -> Result(Nil, Reason) {
  case flow_control {
    ActiveOnce -> arm_once(socket)
    ActiveCount(reads:) -> arm_count(socket, reads)
  }
}

@external(erlang, "genesis_prime_socket_ffi", "arm_once")
fn arm_once(socket: Socket) -> Result(Nil, Reason)

@external(erlang, "genesis_prime_socket_ffi", "arm_count")
fn arm_count(socket: Socket, reads: Int) -> Result(Nil, Reason)

/// Closes the socket.
@external(erlang, "genesis_prime_socket_ffi", "close")
pub fn close(socket socket: Socket) -> Nil

/// Closes a listening socket from any process, which makes the process that
/// waits in `accept` on it get `Closed`, and makes the port refuse new
/// connections.
@external(erlang, "genesis_prime_socket_ffi", "close")
pub fn close_listening(socket socket: ListenSocket) -> Nil

/// The peer's address and port as text, for the log, or `None` when the
/// socket is closed.
@external(erlang, "genesis_prime_socket_ffi", "peer")
pub fn peer(socket socket: Socket) -> Option(String)

/// Adds the socket's events to a selector, each mapped to a message.
pub fn select(
  selector selector: Selector(message),
  mapping mapping: fn(Event) -> message,
) -> Selector(message) {
  selector
  |> process.select_record(tag: data_tag(), fields: 2, mapping: fn(tuple) {
    let assert Ok(bytes) = decode.run(tuple, decode.at([2], decode.bit_array))
      as "gen_tcp sends a binary in binary mode"
    mapping(Received(bytes:))
  })
  |> process.select_record(tag: closed_tag(), fields: 1, mapping: fn(_tuple) {
    mapping(PeerClosed)
  })
  |> process.select_record(tag: error_tag(), fields: 2, mapping: fn(tuple) {
    mapping(Failed(reason: error_reason(tuple)))
  })
  |> process.select_record(tag: passive_tag(), fields: 1, mapping: fn(_tuple) {
    mapping(ReadsUsedUp)
  })
}

/// The reason in a `{tcp_error, Socket, Reason}` message. gen_tcp's reasons
/// are POSIX atoms.
fn error_reason(tuple: decode.Dynamic) -> Reason {
  case decode.run(tuple, decode.at([2], atom.decoder())) {
    Ok(name) ->
      case atom.to_string(name) {
        "closed" -> Closed
        "timeout" -> Timeout
        "eaddrinuse" -> AddressInUse
        "econnreset" -> ConnectionReset
        posix -> Other(posix:)
      }
    Error([decode.DecodeError(expected:, found:, ..), ..]) ->
      Other(posix: "expected " <> expected <> ", found " <> found)
    Error([]) -> Other(posix: "unknown")
  }
}

@external(erlang, "genesis_prime_socket_ffi", "data_tag")
fn data_tag() -> Tag

@external(erlang, "genesis_prime_socket_ffi", "closed_tag")
fn closed_tag() -> Tag

@external(erlang, "genesis_prime_socket_ffi", "error_tag")
fn error_tag() -> Tag

@external(erlang, "genesis_prime_socket_ffi", "passive_tag")
fn passive_tag() -> Tag
