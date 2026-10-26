//// The process that waits for clients on a listening socket. For each client
//// it checks the connection cap, starts a socket owner under the connection
//// supervisor and makes the owner the socket's owner. A client over the cap,
//// or whose owner did not start, is closed at once and logged.

import genesis_prime/connection/socket.{type Socket}
import genesis_prime/connection/socket_owner
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision

/// The supervisor of the socket owners, with the socket each one is started
/// for as the argument of its start.
pub type Connections =
  factory_supervisor.Supervisor(Socket, Subject(socket_owner.Message))

/// What the acceptor needs to start.
pub type Settings {
  Settings(
    port: Int,
    connection_cap: Int,
    connections: process.Name(
      factory_supervisor.Message(Socket, Subject(socket_owner.Message)),
    ),
    listening: fn(Int) -> Nil,
  )
}

/// The acceptor's own message: accept the next client.
pub opaque type Message {
  Accept
}

/// The acceptor as a child of the listener's supervisor, restarted when it
/// ends and given a second to stop. It opens the listening socket when it
/// starts and calls `listening` with the port it got.
pub fn supervised(
  settings settings: Settings,
) -> supervision.ChildSpecification(Subject(Message)) {
  todo as "the acceptor as a worker"
}

/// Starts the acceptor.
fn start(settings: Settings) -> actor.StartResult(Subject(Message)) {
  todo as "open the socket and start accepting"
}
