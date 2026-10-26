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
//// waits in the operating system's buffers.

import genesis_prime/recording.{type Header}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import mug

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

/// Starts a pipe for an accepted connection, waiting for `Begin` or `Abandon`.
/// The caller hands the socket over to the pipe before it sends `Begin`.
pub fn start(_connection: Connection) -> actor.StartResult(Subject(Message)) {
  panic as "shape only: not built"
}
