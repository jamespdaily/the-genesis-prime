//// One connection through the relay: a process that owns the client's socket
//// and its own socket to the server, passes every chunk both ways unchanged
//// and writes each chunk to the connection's recording file.
////
//// The process is a temporary child of the relay's connection supervisor, so
//// a crash ends this connection alone, closes both its sockets and is never
//// restarted: a restart could not rebuild the connection. It writes each chunk
//// to the file before it passes the chunk on, so no byte reaches the other side
//// without being on disk, and it takes the next chunk from a socket only when
//// the last one is passed on, so a side that sends faster than the other reads
//// waits in the operating system's buffers. A chunk is what one receive of the
//// socket returns, and its time is read when the pipe handles it.
////
//// Beside the recording it writes the address it connected to the server from
//// (`session.write_connection`), which is the peer address the server sees for
//// this connection, so a replay can find the draws the connection made.
////
//// A failure the operator can act on, such as a server that is not there, is
//// printed with the file's name and ends the connection. A file that cannot
//// be written crashes the process, so no byte is passed on that is not on disk.

import genesis_prime/recording.{
  type Header, Chunk, ClientToServer, ServerToClient,
}
import genesis_prime/recording/clock
import genesis_prime/recording/listener
import genesis_prime/recording/session
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import mug

/// How long the pipe waits for its initialiser, in milliseconds.
const start_wait_ms = 5000

/// How long the pipe waits for the connection to the server, in milliseconds.
const server_connect_ms = 3000

/// The server the relay passes a connection to.
pub type Server {
  Server(host: String, port: Int)
}

/// What a pipe is started with: the client's socket as accepted, the clock's
/// reading when it was accepted, the file to write, the server to connect to
/// and the header of the recording.
pub type Connection {
  Connection(
    client: mug.Socket,
    accepted_at: Int,
    path: String,
    server: Server,
    header: Header,
  )
}

/// The messages of a pipe.
pub type Message {
  /// The socket now belongs to the pipe: connect to the server, create the
  /// file and start passing chunks.
  Begin
  /// The socket could not be handed over, so the client is gone: stop.
  Abandon
  /// A packet, a close or an error on one of the two sockets.
  Tcp(mug.TcpMessage)
}

/// Where a pipe is: waiting for its socket to be handed over, or passing
/// chunks between the client and this server socket.
type Status {
  AwaitingHandOver
  Passing(server: mug.Socket)
}

type State {
  State(connection: Connection, status: Status)
}

/// Starts a pipe for an accepted connection, waiting for `Begin` or `Abandon`.
/// The caller hands the socket over to the pipe before it sends `Begin`.
pub fn start(connection: Connection) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_wait_ms, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> mug.select_tcp_messages(Tcp)
    actor.initialised(State(connection:, status: AwaitingHandOver))
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case state.status, message {
    AwaitingHandOver, Begin -> begin(state.connection)
    AwaitingHandOver, Abandon -> actor.stop()
    Passing(server:), Tcp(tcp) -> pass(state:, server:, tcp:)
    AwaitingHandOver, Tcp(_) | Passing(_), Begin | Passing(_), Abandon ->
      actor.stop_abnormal("a message the pipe's status does not take")
  }
}

/// Connects to the server and creates the file, and then asks each socket for
/// its first packet. A server that cannot be reached closes the client.
fn begin(connection: Connection) -> actor.Next(State, Message) {
  let options =
    mug.new(connection.server.host, port: connection.server.port)
    |> mug.timeout(server_connect_ms)
    |> mug.ip_version_preference(mug.Ipv4Preferred)
  case mug.connect(options) {
    Error(error) -> {
      io.println_error(
        "could not connect to the server for "
        <> connection.path
        <> ": "
        <> describe_connect_error(error),
      )
      close(connection.client)
      actor.stop()
    }
    Ok(server) -> {
      let assert Ok(Nil) =
        recording.create(at: connection.path, header: connection.header)
        as "the recording file was not created"
      let assert Ok(address) = listener.local_address(server)
        as "the connection to the server has an address"
      let assert Ok(Nil) =
        session.write_connection(
          recording_path: connection.path,
          connection: address,
        )
        as "the connection's address was not written beside the recording"
      io.println("recording " <> connection.path)
      let ready = case
        listener.send_at_once(connection.client),
        listener.send_at_once(server)
      {
        Ok(Nil), Ok(Nil) -> Ok(Nil)
        Error(error), _ | _, Error(error) -> Error(error)
      }
      case ready {
        Ok(Nil) -> {
          mug.receive_next_packet_as_message(connection.client)
          mug.receive_next_packet_as_message(server)
          actor.continue(State(connection:, status: Passing(server:)))
        }
        Error(error) -> {
          io.println_error(
            connection.path
            <> " ended before it passed a chunk: "
            <> mug.describe_error(error),
          )
          close_both(connection.client, server)
          actor.stop()
        }
      }
    }
  }
}

/// Handles what one of the sockets reports: a packet is written to the file and
/// then sent on to the other socket; a close or an error ends the connection.
fn pass(
  state state: State,
  server server: mug.Socket,
  tcp tcp: mug.TcpMessage,
) -> actor.Next(State, Message) {
  let connection = state.connection
  case tcp {
    mug.Packet(socket, bytes) -> {
      let #(direction, to) = case socket == connection.client {
        True -> #(ClientToServer, server)
        False -> #(ServerToClient, connection.client)
      }
      let microseconds = clock.microseconds() - connection.accepted_at
      let assert Ok(Nil) =
        recording.append(
          to: connection.path,
          chunk: Chunk(direction:, microseconds:, bytes:),
        )
        as "a chunk was not written to the recording file"
      case mug.send(to, bytes) {
        Ok(Nil) -> {
          mug.receive_next_packet_as_message(socket)
          actor.continue(state)
        }
        Error(error) -> {
          io.println_error(
            connection.path
            <> " ended, a chunk was not sent on: "
            <> mug.describe_error(error),
          )
          close_both(connection.client, server)
          actor.stop()
        }
      }
    }
    mug.SocketClosed(_) -> {
      io.println(connection.path <> " ended, a side closed the connection")
      close_both(connection.client, server)
      actor.stop()
    }
    mug.TcpError(_, error) -> {
      io.println_error(
        connection.path
        <> " ended, a socket failed: "
        <> mug.describe_error(error),
      )
      close_both(connection.client, server)
      actor.stop()
    }
  }
}

fn close_both(client: mug.Socket, server: mug.Socket) -> Nil {
  close(client)
  close(server)
}

/// Shuts a socket down after the kernel has taken what was sent on it. A
/// socket the other side has already closed is closed.
pub fn close(socket: mug.Socket) -> Nil {
  case mug.shutdown(socket) {
    Ok(Nil) | Error(mug.Closed) | Error(mug.Enotconn) -> Nil
    Error(error) ->
      io.println_error(
        "a socket did not shut down cleanly: " <> mug.describe_error(error),
      )
  }
}

fn describe_connect_error(error: mug.ConnectError) -> String {
  case error {
    mug.ConnectFailedIpv4(ipv4:) -> "IPv4: " <> mug.describe_error(ipv4)
    mug.ConnectFailedIpv6(ipv6:) -> "IPv6: " <> mug.describe_error(ipv6)
    mug.ConnectFailedBoth(ipv4:, ipv6:) ->
      "IPv4: "
      <> mug.describe_error(ipv4)
      <> ", IPv6: "
      <> mug.describe_error(ipv6)
  }
}
