//// The process that owns one client's socket. It reads the socket in the flow
//// control it is given, hands every complete frame to its handler, and ends
//// when the client closes the socket, the socket fails or a limit is broken.
//// A limit that ends it is logged with its reason, and its socket is closed.
////
//// Four limits protect the server from one connection: the size cap of a
//// frame (`frame.size_limit`), the rate limit (`rate_limit`), flow control
//// (`socket.FlowControl`) and the heap ceiling (`capacity`); the connection
//// cap is the listener's. The rules of the first two are in `inbound`; this
//// process reads the clock, the socket and the handler.
////
//// A socket owner is a temporary child of its listener's supervisor: it is
//// never restarted, because the client opens a new connection to log in
//// again.

import genesis_prime/connection/clock.{type Clock}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/rate_limit.{type Rate}
import genesis_prime/connection/socket.{type FlowControl, type Socket}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

/// What a socket owner does with each frame: the game logic, given by whoever
/// starts the listener. It runs in the socket owner's process, so a slow
/// handler holds the owner, and flow control keeps the socket's reads waiting
/// in the runtime meanwhile.
pub type Handler =
  fn(Frame) -> Nil

/// What a socket owner needs to start.
pub type Settings {
  Settings(
    handler: Handler,
    flow_control: FlowControl,
    rate: Rate,
    heap_ceiling_words: Int,
    clock: Clock,
  )
}

/// Every message a socket owner receives. The acceptor sends `SocketGiven`;
/// the rest come from the socket.
pub opaque type Message {
  /// The acceptor made this process the socket's owner.
  SocketGiven
  /// The socket reported something.
  SocketEvent(event: socket.Event)
}

/// Settings with the limits the server measured: active once, the client's
/// rate and the heap ceiling, reading the monotonic clock.
pub fn settings(handler handler: Handler) -> Settings {
  todo as "the measured defaults"
}

/// Starts the owner of `socket`. It sets its heap ceiling first, counting
/// shared binaries, and starts reading only after `socket_given`.
pub fn start(
  settings settings: Settings,
  socket socket: Socket,
) -> actor.StartResult(Subject(Message)) {
  todo as "start the actor"
}

/// Tells the owner that the socket belongs to it, so it starts reading.
pub fn socket_given(owner owner: Subject(Message)) -> Nil {
  todo as "send SocketGiven"
}
