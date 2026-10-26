//// The recording relay: it listens where the client connects, opens the same
//// connection to the server for each client connection, passes every chunk
//// both ways unchanged and writes one recording file for each connection into
//// a folder.
////
//// The tree, with what each part rebuilds from:
//// - the relay's supervisor (rest for one, 3 restarts in 5 seconds), started
////   by `start` under the caller;
//// - the connection supervisor, a factory of pipes, one for each connection.
////   A pipe is temporary and is never rebuilt. The factory is first, so a
////   restart of it restarts the acceptor after it;
//// - the acceptor, which owns the listening socket, waits for a connection,
////   starts a pipe for it, hands the socket over and tells the pipe to begin.
////   A restart listens again on the same port from the settings, and counts
////   its connections from 1.
////
//// What a player sees when a part dies: a pipe that dies closes that one
//// connection; the acceptor that dies closes the listening socket until it is
//// rebuilt. Nothing is saved except the recording files, which each chunk
//// reaches before it is passed on.

import genesis_prime/recording.{type Header}
import genesis_prime/recording/listener.{type Bind}
import genesis_prime/recording/pipe.{type Connection, type Server}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import mug

/// What the relay is started with. `listen_port` 0 takes a free port, which
/// `Relay` reports. `connections` is the name the connection supervisor is
/// registered under, made by the caller with `process.new_name`.
pub type Settings {
  Settings(
    bind: Bind,
    listen_port: Int,
    server: Server,
    folder: String,
    header: Header,
    connections: Name(
      factory_supervisor.Message(Connection, Subject(pipe.Message)),
    ),
  )
}

/// A relay that is running: its supervisor and the port it listens on.
pub type Relay {
  Relay(supervisor: Pid, port: Int)
}

/// Why the relay did not start.
pub type Failure {
  /// The relay could not listen, for the reason the operating system gave.
  CouldNotListen(mug.Error)
  /// The tree failed to start for another reason.
  TreeDidNotStart(actor.StartError)
}

/// Starts the relay under the calling process and returns once it listens.
/// It stops when the caller ends.
pub fn start(_settings: Settings) -> Result(Relay, Failure) {
  panic as "shape only: not built"
}
