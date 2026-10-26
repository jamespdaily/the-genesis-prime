//// A listening TCP socket and the calls on the sockets it accepts, which `mug`
//// (a TCP client) does not have. An accepted socket is a `mug.Socket`: `mug`
//// sends on it, receives on it and shuts it down.
////
//// The Erlang helper `recording_socket_ffi` holds the two calls that return a
//// bare `ok`, which no Gleam external can read as a `Result`.

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

/// Starts listening on `port`, or on a free port when it is 0.
pub fn listen(_bind: Bind, _port: Int) -> Result(Listener, mug.Error) {
  panic as "shape only: not built"
}

/// The port a listener listens on.
pub fn port(_listener: Listener) -> Result(Int, mug.Error) {
  panic as "shape only: not built"
}

/// Waits for the next connection for as long as it takes.
pub fn accept(_listener: Listener) -> Result(mug.Socket, mug.Error) {
  panic as "shape only: not built"
}

/// Waits up to `within` milliseconds for the next connection; the error is
/// `mug.Timeout` when none comes.
pub fn accept_within(
  _listener: Listener,
  within _within: Int,
) -> Result(mug.Socket, mug.Error) {
  panic as "shape only: not built"
}

/// Makes `pid` the process that owns the socket, so the messages of an active
/// socket go to it. Only the socket's current owner can call it.
pub fn hand_over(_socket: mug.Socket, to _pid: Pid) -> Result(Nil, mug.Error) {
  panic as "shape only: not built"
}

/// Turns off the delay that holds a small send back to join the next one, so
/// the relay adds none to the exchange it carries.
pub fn send_at_once(_socket: mug.Socket) -> Result(Nil, mug.Error) {
  panic as "shape only: not built"
}
