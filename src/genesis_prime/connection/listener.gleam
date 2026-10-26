//// A listener: the supervisor of one port's clients. Its children are the
//// connection supervisor, whose children are the socket owners, and the
//// acceptor. The auth and the game each start one.
////
//// It is a service subtree, one for one with 3 restarts in 5 seconds, so a
//// fault that survives three rebuilds stops the subtree and reaches the top.
//// Socket owners are temporary children: a connection that ends is not
//// restarted.

import genesis_prime/connection/socket_owner
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision

/// What a listener needs: the port, the cap on connections, what each socket
/// owner is started with, and what to do when the port is open.
pub type Settings {
  Settings(
    port: Int,
    connection_cap: Int,
    owner: socket_owner.Settings,
    listening: fn(Int) -> Nil,
  )
}

/// Settings for `port` with the measured connection cap and owner settings,
/// handing each frame to `handler`.
pub fn settings(
  port port: Int,
  handler handler: socket_owner.Handler,
) -> Settings {
  todo as "the measured defaults"
}

/// The listener as a child of a supervisor.
pub fn supervised(
  settings settings: Settings,
) -> supervision.ChildSpecification(Supervisor) {
  todo as "the connection supervisor and the acceptor under one supervisor"
}
