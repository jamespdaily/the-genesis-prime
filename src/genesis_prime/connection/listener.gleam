//// A listener: the supervisor of one port's clients. Its children are the
//// connection supervisor, whose children are the socket owners, and the
//// acceptor. The auth and the game each start one.
////
//// It is a service subtree, one for one with 3 restarts in 5 seconds, so a
//// fault that survives three rebuilds stops the subtree and reaches the top.
//// Socket owners are temporary children: a connection that ends is not
//// restarted.

import genesis_prime/connection/acceptor
import genesis_prime/connection/capacity
import genesis_prime/connection/socket_owner
import genesis_prime/shutdown
import gleam/erlang/process
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision

/// How long the connection supervisor gives a socket owner to stop, in
/// milliseconds: an owner holds nothing to flush.
const owner_shutdown_ms = 1000

/// What a listener needs: the port, the cap on connections, what each socket
/// owner is started with, what to do when the port is open, and the settings
/// of the shutdown coordinator that the listener and its connections register
/// with.
pub type Settings {
  Settings(
    port: Int,
    connection_cap: Int,
    owner: socket_owner.Settings,
    listening: fn(Int) -> Nil,
    shutdown: shutdown.Settings,
  )
}

/// Settings for `port` with the measured connection cap and owner settings,
/// handing each frame to `handler`, and registering with the coordinator of
/// `shutdown`.
pub fn settings(
  port port: Int,
  handler handler: socket_owner.Handler,
  shutdown shutdown: shutdown.Settings,
) -> Settings {
  Settings(
    port:,
    connection_cap: capacity.connection_cap(),
    owner: socket_owner.settings(handler:),
    listening: fn(_port) { Nil },
    shutdown:,
  )
}

/// The listener as a child of a supervisor. The connection supervisor starts
/// first, so the acceptor finds it when its first client arrives.
pub fn supervised(
  settings settings: Settings,
) -> supervision.ChildSpecification(Supervisor) {
  let connections = process.new_name("connections")
  let connection_supervisor =
    factory_supervisor.worker_child(fn(socket) {
      socket_owner.start(
        settings: settings.owner,
        socket:,
        shutdown: settings.shutdown,
      )
    })
    |> factory_supervisor.named(connections)
    |> factory_supervisor.restart_strategy(supervision.Temporary)
    |> factory_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> factory_supervisor.timeout(ms: owner_shutdown_ms)
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
  |> static_supervisor.add(factory_supervisor.supervised(connection_supervisor))
  |> static_supervisor.add(
    acceptor.supervised(acceptor.Settings(
      port: settings.port,
      connection_cap: settings.connection_cap,
      heap_ceiling_words: settings.owner.heap_ceiling_words,
      connections:,
      listening: settings.listening,
      shutdown: settings.shutdown,
    )),
  )
  |> static_supervisor.supervised
}
