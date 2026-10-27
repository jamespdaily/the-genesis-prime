//// A port the server listens on: a Ranch listener, added to the supervision
//// tree as one child, whose connections each run a shell
//// (genesis_prime/connection/shell).
////
//// ```
//// server supervisor (one-for-one)
////  └─ listener: Ranch's embedded supervisor        permanent
////       ├─ acceptors                                 Ranch's
////       └─ connections supervisor                    Ranch's
////            └─ one shell process per connection     temporary
//// ```
////
//// A connection that crashes ends alone: Ranch never restarts a connection.
//// A listener that crashes is restarted by the server supervisor, which drops
//// its connections; a restart cannot rebuild a connection, so each client
//// connects again. When the tree stops, the listener stops accepting and each
//// connection gets `shutdown_ms` to end before it is killed.

import genesis_prime/connection/shell.{type Settings}
import gleam/otp/supervision.{type ChildSpecification}

/// What one listener is started with.
pub type Listener(settings, state, message, answer, outgoing, request) {
  Listener(
    /// The listener's name in Ranch, unique on the node, such as `"auth"`.
    name: String,
    /// The TCP port, or 0 for one the system picks.
    port: Int,
    /// How long each connection may take to end when the tree stops.
    shutdown_ms: Int,
    connection: Settings(settings, state, message, answer, outgoing, request),
  )
}

/// The listener as a child of a supervisor.
pub fn supervised(
  listener: Listener(settings, state, message, answer, outgoing, request),
) -> ChildSpecification(Nil) {
  todo as "the build follows the shape commit"
}

/// The port a running listener listens on, as Ranch reports it.
pub fn port(name: String) -> Result(Int, Nil) {
  todo as "the build follows the shape commit"
}
