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
//// A connection that crashes ends alone: Ranch never restarts a connection.
//// A listener that crashes is restarted by the server supervisor, which drops
//// its connections; a restart cannot rebuild a connection, so each client
//// connects again. When the tree stops, each connection gets `Stopping` and
//// the connection settings' `shutdown_ms` to end before it is killed.

import genesis_prime/connection/shell.{type Settings}
import gleam/erlang/process.{type Name, type Pid}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// What one listener is started with.
pub type Listener(settings, state, message, answer, outgoing, request) {
  Listener(
    /// The listener's name in Ranch, unique on the node: made once, with
    /// `process.new_name`.
    name: Name(Nil),
    /// The TCP port, or 0 for one the system picks.
    port: Int,
    connection: Settings(settings, state, message, answer, outgoing, request),
  )
}

/// Why Ranch did not start the listener, as Ranch reported it.
type StartFailure {
  CouldNotListen(reason: String)
}

/// The listener as a child of a supervisor.
pub fn supervised(
  listener: Listener(settings, state, message, answer, outgoing, request),
) -> ChildSpecification(Nil) {
  supervision.supervisor(fn() {
    case
      start_listener(
        listener.name,
        listener.port,
        listener.connection.shutdown_ms,
        listener.connection,
      )
    {
      Ok(pid) -> Ok(actor.Started(pid:, data: Nil))
      Error(CouldNotListen(reason:)) -> Error(actor.InitFailed(reason))
    }
  })
}

/// The port a running listener listens on, as Ranch reports it.
@external(erlang, "connection_shell_ffi", "listener_port")
pub fn port(name: Name(Nil)) -> Result(Int, Nil)

@external(erlang, "connection_shell_ffi", "start_listener")
fn start_listener(
  name: Name(Nil),
  port: Int,
  shutdown_ms: Int,
  settings: Settings(settings, state, message, answer, outgoing, request),
) -> Result(Pid, StartFailure)
