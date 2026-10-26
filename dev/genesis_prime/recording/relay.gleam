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
////   A restart listens again on the same port from the settings and numbers
////   its connections after the files the folder holds.
////
//// What a client sees when a part dies: a pipe that dies closes that one
//// connection; the acceptor that dies closes the listening socket until it is
//// rebuilt. Nothing is saved except the recording files, which each chunk
//// reaches before it is passed on. A file is named `<role>-<number>.recording`,
//// the number counting from 1 in the order the connections were accepted. The
//// file `<role>-<number>.connection` beside it holds the connection's role, the
//// address the relay connected to the server from, and its incarnation.
////
//// The relay serves one client on a network its operator trusts: it has no
//// connection cap, no packet size cap and no rate limit, and each socket is
//// read one packet at a time, so a side that sends faster than the other
//// reads waits in the operating system's buffers.

import genesis_prime/recording.{type Header}
import genesis_prime/recording/clock
import genesis_prime/recording/listener.{type Bind, type Listener}
import genesis_prime/recording/pipe.{type Connection, type Server}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import mug
import simplifile

/// How long `start` waits for the acceptor's report of its port, in
/// milliseconds. The acceptor sends it before the tree finishes starting, so
/// the wait is for a message that is already on its way.
const report_wait_ms = 2000

/// How long the acceptor has to initialise, in milliseconds.
const acceptor_start_ms = 5000

/// What the relay is started with. `listen_port` 0 takes a free port, which
/// `Relay` reports. `connections` is the name the connection supervisor is
/// registered under, made by the caller with `process.new_name`. `folder` is a
/// folder that exists.
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

/// What the acceptor tells `start` once it has tried to listen: the port, or
/// why it could not.
type Listening =
  Result(Int, mug.Error)

/// Starts the relay under the calling process and returns once it listens.
/// It stops when the caller ends.
pub fn start(settings: Settings) -> Result(Relay, Failure) {
  let listening: Subject(Listening) = process.new_subject()
  let started =
    static_supervisor.new(static_supervisor.RestForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(
      factory_supervisor.worker_child(pipe.start)
      |> factory_supervisor.named(settings.connections)
      |> factory_supervisor.restart_strategy(supervision.Temporary)
      |> factory_supervisor.timeout(ms: 1000)
      |> factory_supervisor.supervised,
    )
    |> static_supervisor.add(
      supervision.worker(fn() { start_acceptor(settings, listening) })
      |> supervision.timeout(ms: 1000),
    )
    |> static_supervisor.start
  case process.receive(listening, within: report_wait_ms), started {
    Ok(Error(error)), _ -> Error(CouldNotListen(error))
    Ok(Ok(port)), Ok(supervisor) -> Ok(Relay(supervisor: supervisor.pid, port:))
    _, Error(error) -> Error(TreeDidNotStart(error))
    Error(Nil), Ok(_) ->
      Error(TreeDidNotStart(actor.InitFailed("the acceptor reported no port")))
  }
}

/// The messages of the acceptor: one, to wait for the next connection.
type AcceptorMessage {
  Accept
}

type Acceptor {
  Acceptor(
    settings: Settings,
    listener: Listener,
    connections: factory_supervisor.Supervisor(
      Connection,
      Subject(pipe.Message),
    ),
    next_number: Int,
    myself: Subject(AcceptorMessage),
  )
}

/// Starts the acceptor: it listens, reports the port on `listening` and asks
/// itself for the first connection. A folder that cannot be listed or a port
/// that cannot be listened on fails the start.
fn start_acceptor(
  settings: Settings,
  listening: Subject(Listening),
) -> actor.StartResult(Subject(AcceptorMessage)) {
  actor.new_with_initialiser(acceptor_start_ms, fn(myself) {
    case listen(settings) {
      Error(error) -> {
        process.send(listening, Error(error))
        Error("could not listen: " <> mug.describe_error(error))
      }
      Ok(#(socket, port)) ->
        case recordings_of_role(settings) {
          Error(error) ->
            Error(
              "could not read the folder "
              <> settings.folder
              <> ": "
              <> simplifile.describe_error(error),
            )
          Ok(existing) -> {
            process.send(listening, Ok(port))
            process.send(myself, Accept)
            actor.initialised(Acceptor(
              settings:,
              listener: socket,
              connections: factory_supervisor.get_by_name(settings.connections),
              next_number: existing + 1,
              myself:,
            ))
            |> actor.returning(myself)
            |> Ok
          }
        }
    }
  })
  |> actor.on_message(accept_next)
  |> actor.start
}

fn listen(settings: Settings) -> Result(#(Listener, Int), mug.Error) {
  use socket <- result.try(listener.listen(
    bind: settings.bind,
    port: settings.listen_port,
  ))
  use port <- result.map(listener.port(socket))
  #(socket, port)
}

/// How many recordings of the relay's role the folder holds.
fn recordings_of_role(settings: Settings) -> Result(Int, simplifile.FileError) {
  let prefix = recording.role_name(settings.header.role) <> "-"
  use names <- result.map(simplifile.read_directory(settings.folder))
  list.count(names, fn(name) {
    string.starts_with(name, prefix) && string.ends_with(name, ".recording")
  })
}

/// Waits for the next connection, and starts, hands over to and begins a pipe
/// for it, and then asks for the one after. A connection that gets no pipe is
/// closed, and the reason is printed.
fn accept_next(
  state: Acceptor,
  message: AcceptorMessage,
) -> actor.Next(Acceptor, AcceptorMessage) {
  let Accept = message
  case listener.accept(state.listener) {
    Ok(client) -> {
      let connection =
        pipe.Connection(
          client:,
          accepted_at: clock.microseconds(),
          path: path_of(state),
          server: state.settings.server,
          header: state.settings.header,
        )
      hand_to_pipe(state.connections, connection)
      process.send(state.myself, Accept)
      actor.continue(Acceptor(..state, next_number: state.next_number + 1))
    }
    Error(error) ->
      actor.stop_abnormal("accepting failed: " <> mug.describe_error(error))
  }
}

/// The file of the next connection: `<role>-<number>.recording` in the folder,
/// the number written with three digits.
fn path_of(state: Acceptor) -> String {
  state.settings.folder
  <> "/"
  <> recording.role_name(state.settings.header.role)
  <> "-"
  <> string.pad_start(int.to_string(state.next_number), to: 3, with: "0")
  <> ".recording"
}

fn hand_to_pipe(
  connections: factory_supervisor.Supervisor(Connection, Subject(pipe.Message)),
  connection: Connection,
) -> Nil {
  case factory_supervisor.start_child(connections, connection) {
    Ok(started) ->
      case listener.hand_over(connection.client, to: started.pid) {
        Ok(Nil) -> process.send(started.data, pipe.Begin)
        Error(error) -> {
          io.println_error(
            connection.path
            <> " was not recorded, its socket could not be handed over: "
            <> mug.describe_error(error),
          )
          process.send(started.data, pipe.Abandon)
        }
      }
    Error(error) -> {
      io.println_error(
        connection.path
        <> " was not recorded, no pipe started: "
        <> describe_start_error(error),
      )
      pipe.close(connection.client)
    }
  }
}

fn describe_start_error(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "it took too long to start"
    actor.InitFailed(reason) -> reason
    actor.InitExited(_) -> "it exited as it started"
  }
}
