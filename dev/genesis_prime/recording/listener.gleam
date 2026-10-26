//// A listening TCP socket and the calls on the sockets it accepts, which `mug`
//// (a TCP client) does not have. An accepted socket is a `mug.Socket`: `mug`
//// sends on it, receives on it and shuts it down.
////
//// The Erlang helper `recording_socket_ffi` holds the calls that return a bare
//// `ok`, which no Gleam external can read as a `Result`, and the socket's own
//// address as text.

import gleam/erlang/process.{type Pid}
import mug

/// A socket that accepts connections.
pub type Listener

/// Which addresses a listener accepts connections on: the loopback only, or
/// every IPv4 address of the machine.
pub type Bind {
  Loopback
  AllInterfaces
}

/// The options of `gen_tcp:listen/2` this module sets. A constructor without a
/// field is the atom of its name in lower case, and one with a field is the
/// tuple of that atom and the field, which is how Erlang writes the option.
type ListenOption {
  Binary
  Inet
  Active(Bool)
  Reuseaddr(Bool)
  Nodelay(Bool)
  Backlog(Int)
  Ip(#(Int, Int, Int, Int))
}

/// How many connections may wait to be accepted.
const backlog = 128

/// Starts listening on `port`, or on a free port when it is 0. The sockets it
/// accepts give bytes, hold what they receive until `mug` asks for it, and
/// send at once.
pub fn listen(bind bind: Bind, port port: Int) -> Result(Listener, mug.Error) {
  let address = case bind {
    Loopback -> #(127, 0, 0, 1)
    AllInterfaces -> #(0, 0, 0, 0)
  }
  gen_tcp_listen(port, [
    Inet,
    Binary,
    Active(False),
    Reuseaddr(True),
    Nodelay(True),
    Backlog(backlog),
    Ip(address),
  ])
}

@external(erlang, "gen_tcp", "listen")
fn gen_tcp_listen(
  port: Int,
  options: List(ListenOption),
) -> Result(Listener, mug.Error)

/// The port a listener listens on.
@external(erlang, "inet", "port")
pub fn port(listener: Listener) -> Result(Int, mug.Error)

/// Waits for the next connection for as long as it takes.
@external(erlang, "gen_tcp", "accept")
pub fn accept(listener: Listener) -> Result(mug.Socket, mug.Error)

/// Waits up to `within` milliseconds for the next connection; the error is
/// `mug.Timeout` when none comes.
@external(erlang, "gen_tcp", "accept")
pub fn accept_within(
  listener: Listener,
  within within: Int,
) -> Result(mug.Socket, mug.Error)

/// Makes `pid` the process that owns the socket, so the messages of an active
/// socket go to it. Only the socket's current owner can call it.
@external(erlang, "recording_socket_ffi", "hand_over")
pub fn hand_over(socket: mug.Socket, to pid: Pid) -> Result(Nil, mug.Error)

/// Turns off the delay that holds a small send back to join the next one, so
/// the relay adds none to the exchange it carries.
@external(erlang, "recording_socket_ffi", "send_at_once")
pub fn send_at_once(socket: mug.Socket) -> Result(Nil, mug.Error)

/// The socket's own address and port as text, written as the server writes the
/// peer address of the connection at the other end, so the two are the same
/// text.
@external(erlang, "recording_socket_ffi", "local_address")
pub fn local_address(socket: mug.Socket) -> Result(String, mug.Error)

/// Closes the sending side of the socket and leaves the receiving side open,
/// so the other side reads the end of the stream and what it still has to send
/// can be read.
@external(erlang, "recording_socket_ffi", "finish_sending")
pub fn finish_sending(socket: mug.Socket) -> Result(Nil, mug.Error)
