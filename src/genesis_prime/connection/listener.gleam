//// A port the server listens on: a Ranch listener, added to the supervision
//// tree as one child, whose connections each run a shell
//// (genesis_prime/connection/shell).
////
//// ```
//// server supervisor (one-for-one)
////  └─ listener: Ranch's embedded supervisor        permanent
////       ├─ acceptors                                 Ranch's
////       └─ connections supervisor (one)              Ranch's
////            └─ one shell process per connection     temporary
//// ```
////
//// A listener holds at most its `max_connections` (one acceptor, so exactly
//// that many): a client past it waits in the system's accept queue, gets no
//// hello, and is taken when a connection ends. Ranch refuses before any
//// process exists, so no recording shows it.
////
//// A connection that crashes ends alone: Ranch never restarts a connection.
//// A listener that crashes is restarted by the server supervisor, which drops
//// its connections; a restart cannot rebuild a connection, so each client
//// connects again. When the tree stops, each connection gets `Stopping` and
//// the connection settings' `shutdown_ms` to end before it is killed.
////
//// A listener's own stop closes its listening socket before it stops its
//// connections (Ranch lists the connection supervisor first, so it stops last),
//// but the tree stops one listener after another. `stop_accepting` closes a
//// listener's socket alone, so the closer (genesis_prime/connection/closer)
//// can close every listener before any connection is stopped.

import genesis_prime/connection/shell.{type Settings}
import gleam/erlang/process.{type Name, type Pid}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// What one listener is started with.
pub type Listener(settings, state, message, answer, request) {
  Listener(
    /// The listener's name in Ranch, unique on the node: made once, with
    /// `process.new_name`.
    name: Name(Nil),
    /// The TCP port, or 0 for one the system picks.
    port: Int,
    /// The most connections the listener holds at once. Past it a new client
    /// waits in the system's accept queue, gets no hello, and is taken when a
    /// connection ends (Ranch's `max_connections`). The listener has one
    /// acceptor, since Ranch can take one connection past the limit for each
    /// extra acceptor.
    max_connections: Int,
    connection: Settings(settings, state, message, answer, request),
  )
}

/// Why Ranch did not start the listener, as Ranch reported it.
type StartFailure {
  CouldNotListen(reason: String)
}

/// The listener as a child of a supervisor.
pub fn supervised(
  listener: Listener(settings, state, message, answer, request),
) -> ChildSpecification(Nil) {
  supervision.supervisor(fn() {
    case
      start_listener(
        listener.name,
        listener.port,
        listener.max_connections,
        listener.connection.shutdown_ms,
        listener.connection,
      )
    {
      Ok(pid) -> Ok(actor.Started(pid:, data: Nil))
      Error(CouldNotListen(reason:)) -> Error(actor.InitFailed(reason))
    }
  })
}

/// Why Ranch could not give or do something for a listener, as it reported it.
pub type ListenerError {
  /// No listener runs under the name, as when its supervisor is restarting it
  /// or ends while the call waits.
  ListenerNotRunning
  /// The listener's listening socket is closed (`stop_accepting`), so it has
  /// no port.
  ListenerNotListening
  /// Ranch refused, with this reason.
  RanchFailed(reason: String)
}

/// A sentence for the log that says why Ranch could not do it.
pub fn describe(error: ListenerError) -> String {
  case error {
    ListenerNotRunning -> "no listener runs under the name"
    ListenerNotListening -> "the listener's socket is closed"
    RanchFailed(reason:) -> "Ranch failed: " <> reason
  }
}

/// The port a running listener listens on, as Ranch reports it.
@external(erlang, "connection_shell_ffi", "listener_port")
pub fn port(name: Name(Nil)) -> Result(Int, ListenerError)

/// Closes the listener's listening socket, so a new connect is refused, and
/// leaves the connections it already holds running. `Ok` also for a listener
/// already closed.
@external(erlang, "connection_shell_ffi", "suspend_listener")
pub fn stop_accepting(name: Name(Nil)) -> Result(Nil, ListenerError)

@external(erlang, "connection_shell_ffi", "start_listener")
fn start_listener(
  name: Name(Nil),
  port: Int,
  max_connections: Int,
  shutdown_ms: Int,
  settings: Settings(settings, state, message, answer, request),
) -> Result(Pid, StartFailure)
