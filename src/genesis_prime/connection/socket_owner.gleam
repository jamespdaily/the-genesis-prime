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

import genesis_prime/connection/capacity
import genesis_prime/connection/clock.{type Clock}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/inbound.{type Inbound}
import genesis_prime/connection/rate_limit.{type Rate}
import genesis_prime/connection/socket.{type FlowControl, type Socket}
import genesis_prime/telemetry/log.{type Who}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor

/// How long the owner has to start, in milliseconds.
const start_deadline_ms = 5000

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

/// What the owner is doing: waiting for the acceptor to give it the socket,
/// or reading it.
type Status {
  AwaitingSocket
  Reading(inbound: Inbound)
}

type State {
  State(settings: Settings, socket: Socket, status: Status)
}

/// Who the socket owner's lines are from: the process, by its name. A
/// connection has no account until it logs in.
const owner_who =
  log.Who(
    account: None,
    actor: None,
    place: Some(log.Process("socket_owner")),
    message: None,
  )

/// The reads the runtime hands an owner before it asks for more: 32. At 800
/// connections each sending 120 frames a second, a server's CPU time was
/// 1.092 cores with `ActiveOnce`, 0.948 with 8 reads and 0.868 with 32, the
/// median of 5 rounds, every round of 32 below every round of once; the
/// longest mailbox read was 1, 2 and 2 messages. 32 saves 0.224 of a core,
/// above the 0.05 that makes a mode worth its larger mailbox bound.
const reads_per_arm = 32

/// Settings with the limits the server measured: `reads_per_arm` reads at a
/// time, the client's rate and the heap ceiling, reading the monotonic clock.
pub fn settings(handler handler: Handler) -> Settings {
  Settings(
    handler:,
    flow_control: socket.ActiveCount(reads: reads_per_arm),
    rate: rate_limit.client_rate(),
    heap_ceiling_words: capacity.heap_ceiling_words(),
    clock: clock.monotonic_milliseconds,
  )
}

/// Starts the owner of `socket`. It sets its heap ceiling first, counting
/// shared binaries, and starts reading only after `socket_given`.
pub fn start(
  settings settings: Settings,
  socket socket: Socket,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_ms, fn(subject) {
    limit_heap(settings.heap_ceiling_words)
    keep_messages_off_heap()
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> socket.select(SocketEvent)
    let state = State(settings:, socket:, status: AwaitingSocket)
    Ok(
      actor.initialised(state)
      |> actor.selecting(selector)
      |> actor.returning(subject),
    )
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Tells the owner that the socket belongs to it, so it starts reading.
pub fn socket_given(owner owner: Subject(Message)) -> Nil {
  process.send(owner, SocketGiven)
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message, state.status {
    SocketGiven, AwaitingSocket -> {
      let inbound =
        inbound.new(
          rate: state.settings.rate,
          now_milliseconds: state.settings.clock(),
        )
      arm(State(..state, status: Reading(inbound:)))
    }
    SocketGiven, Reading(..) -> actor.continue(state)
    SocketEvent(socket.Received(bytes:)), Reading(inbound:) ->
      receive(state:, inbound:, bytes:)
    SocketEvent(socket.ReadsUsedUp), Reading(..) -> arm(state)
    SocketEvent(socket.PeerClosed), Reading(..) ->
      end_connection(state, log.info, "the client closed the socket")
    SocketEvent(socket.Failed(reason:)), Reading(..) ->
      end_connection(
        state,
        log.warning,
        "the socket failed: " <> socket.describe(reason),
      )
    SocketEvent(_), AwaitingSocket ->
      actor.stop_abnormal(
        "the socket reported before it was given to its owner",
      )
  }
}

/// Cuts the bytes into frames, hands each to the handler and asks the socket
/// for more, unless a limit ended the connection.
fn receive(
  state state: State,
  inbound inbound: Inbound,
  bytes bytes: BitArray,
) -> actor.Next(State, Message) {
  let #(inbound, effects) =
    inbound.receive(
      inbound:,
      received: bytes,
      now_milliseconds: state.settings.clock(),
    )
  let state = State(..state, status: Reading(inbound:))
  let ended =
    list.find_map(effects, fn(effect) {
      case effect {
        inbound.End(reason:) -> Ok(reason)
        inbound.Deliver(..) -> Error(Nil)
      }
    })
  list.each(effects, fn(effect) {
    case effect {
      inbound.Deliver(frame:) -> state.settings.handler(frame)
      inbound.End(..) -> Nil
    }
  })
  case ended {
    Ok(reason) -> end_connection(state, log.warning, inbound.describe(reason:))
    Error(Nil) ->
      case state.settings.flow_control {
        socket.ActiveOnce -> arm(state)
        socket.ActiveCount(..) -> actor.continue(state)
      }
  }
}

/// Asks the socket for the next reads in the owner's flow control.
fn arm(state: State) -> actor.Next(State, Message) {
  case socket.arm(state.socket, state.settings.flow_control) {
    Ok(Nil) -> actor.continue(state)
    Error(socket.Closed) ->
      end_connection(state, log.info, "the client closed the socket")
    Error(reason) ->
      end_connection(
        state,
        log.warning,
        "the socket failed: " <> socket.describe(reason),
      )
  }
}

/// Closes the socket, logs why the connection ended and stops the owner
/// normally.
fn end_connection(
  state: State,
  write: fn(Who, String) -> Nil,
  why: String,
) -> actor.Next(State, Message) {
  socket.close(state.socket)
  write(owner_who, "connection ended: " <> why)
  actor.stop()
}

/// Sets the calling process's heap ceiling in words, killing it when it needs
/// more, shared binaries counted, and logging the kill.
@external(erlang, "genesis_prime_socket_ffi", "limit_heap")
fn limit_heap(words: Int) -> Nil

/// Keeps the calling process's waiting messages off its heap.
@external(erlang, "genesis_prime_socket_ffi", "keep_messages_off_heap")
fn keep_messages_off_heap() -> Nil
