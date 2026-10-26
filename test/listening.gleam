//// A listener started inside a test, on a free port, under the real top
//// supervisor's settings, with a handler that reports every frame a socket
//// owner hands it. A test waits for those reports, never for time.

import genesis_prime/connection/capacity
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/listener
import genesis_prime/connection/socket_owner
import genesis_prime/server
import genesis_prime/shutdown
import gleam/bit_array
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/static_supervisor
import gleam/string
import tcp_client.{type Client}

/// How long a test waits for one event that must happen at once, in
/// milliseconds.
pub const event_wait_ms = 2000

/// A frame the handler received: the socket owner that received it, which
/// runs the handler, and the subject that frees the owner when the listener
/// was started to hold it.
pub type Received {
  Received(owner: Pid, frame: Frame, release: Subject(Nil))
}

/// How the listener is started.
pub type Config {
  Config(
    owner: fn(socket_owner.Settings) -> socket_owner.Settings,
    connection_cap: Int,
    hold: Bool,
  )
}

/// A running listener: the port it was given, its supervisor, its acceptor, the
/// frames its handler reports, and the settings of the shutdown coordinator it
/// registered with, started beside it.
pub type Running {
  Running(
    port: Int,
    supervisor: Pid,
    acceptor: Pid,
    frames: Subject(Received),
    shutdown: shutdown.Settings,
  )
}

/// How long the coordinator gives connections to close once told to, in
/// milliseconds. Long, so a connection that closes when told is never near it
/// and a test that would wait it out fails by its own deadline instead.
const drain_deadline_ms = 30_000

/// How long the coordinator gives saving workers to flush, in milliseconds. A
/// listener has none.
const flush_deadline_ms = 1000

/// The measured defaults, with a handler that frees the owner at once.
pub fn config() -> Config {
  Config(
    owner: fn(settings) { settings },
    connection_cap: capacity.connection_cap(),
    hold: False,
  )
}

/// Starts a listener on a free port. With `hold` set, each handler call waits
/// until the test sends its `release` subject, so the owner is busy.
pub fn start(config: Config) -> Running {
  let frames = process.new_subject()
  let ports = process.new_subject()
  let handler = fn(frame) {
    let release = process.new_subject()
    process.send(frames, Received(owner: process.self(), frame:, release:))
    case config.hold {
      True -> process.receive_forever(release)
      False -> Nil
    }
  }
  let coordinator = shutdown.new(drain_deadline_ms:, flush_deadline_ms:)
  let defaults = listener.settings(port: 0, handler:, shutdown: coordinator)
  let settings =
    listener.Settings(
      ..defaults,
      connection_cap: config.connection_cap,
      owner: config.owner(defaults.owner),
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
  Running(
    port:,
    supervisor: started.pid,
    acceptor:,
    frames:,
    shutdown: coordinator,
  )
}

/// Connects a client to the listener.
pub fn connect(running: Running) -> Client {
  let assert Ok(client) = tcp_client.connect(running.port)
    as "the client could not connect to the listener"
  client
}

/// The next frame the handler received, or an error when none arrives within
/// the wait.
pub fn next(running: Running) -> Result(Received, Nil) {
  process.receive(running.frames, event_wait_ms)
}

/// Waits up to `event_wait_ms` for the monitored process to end and returns
/// why, or an error when it is still running. A test monitors a process before
/// the event that ends it, because a process that has already ended reports
/// a different reason.
pub fn await_down(monitor: process.Monitor) -> Result(process.ExitReason, Nil) {
  let down =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: event_wait_ms)
  case down {
    Ok(process.ProcessDown(reason:, ..)) -> Ok(reason)
    Ok(process.PortDown(..)) | Error(Nil) -> Error(Nil)
  }
}

/// The bytes of a frame with `size` body bytes.
pub fn frame_of(message_id message_id: Int, size size: Int) -> BitArray {
  let assert Ok(bytes) =
    frame.encode(
      message_id:,
      body: bit_array.from_string(string.repeat("a", size)),
    )
    as "the frame is within the size limit"
  bytes
}
