//// A listener started inside a test for a protocol, on a free port, under the
//// real top supervisor's settings, with a coordinator of its own. The test's
//// conversation reports what it sees to subjects the test made, and the test
//// waits for those reports, never for time.

import genesis_prime/connection/listener
import genesis_prime/connection/socket_owner.{type Protocol}
import genesis_prime/server
import genesis_prime/shutdown
import gleam/erlang/process.{type Pid}
import gleam/otp/static_supervisor
import tcp_client.{type Client}

/// How long a test waits for one event that must happen at once, in
/// milliseconds.
pub const event_wait_ms = 2000

/// A running listener: its port and its acceptor.
pub type Running {
  Running(port: Int, supervisor: Pid, acceptor: Pid)
}

/// Starts a listener on a free port serving `protocol`, with `owner` adjusting
/// the socket owners' settings.
pub fn start(
  protocol protocol: Protocol,
  owner owner: fn(socket_owner.Settings) -> socket_owner.Settings,
) -> Running {
  let ports = process.new_subject()
  let coordinator =
    shutdown.new(drain_deadline_ms: 30_000, flush_deadline_ms: 1000)
  let defaults =
    listener.protocol_settings(port: 0, protocol:, shutdown: coordinator)
  let settings =
    listener.Settings(
      ..defaults,
      owner: owner(defaults.owner),
      listening: fn(port) { process.send(ports, #(port, process.self())) },
    )
  let assert Ok(started) =
    server.supervisor()
    |> static_supervisor.add(shutdown.supervised(coordinator))
    |> static_supervisor.add(listener.supervised(settings))
    |> static_supervisor.start
    as "the listener did not start"
  let assert Ok(#(port, acceptor)) = process.receive(ports, event_wait_ms)
    as "the listener did not report its port"
  Running(port:, supervisor: started.pid, acceptor:)
}

/// Connects a client to the listener.
pub fn connect(running: Running) -> Client {
  let assert Ok(client) = tcp_client.connect(running.port)
    as "the client could not connect to the listener"
  client
}
