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
//// What the owner does for a protocol is given by whoever starts the listener
//// as a `Protocol`: the mode the owner reads in, frames or raw bytes, and what
//// happens when a client connects. Each connection has its own `Conversation`,
//// which the protocol's connect step makes and each reaction replaces, so a
//// connection's state is the conversation's own and no other connection reads
//// it. A reaction says what to write to the socket, in order, and whether to
//// close it after. A game connection reads frames; the STS login's
//// connection reads raw bytes, because its protocol is text with its own
//// framing and then RC4.
////
//// A conversation can also be woken by messages other processes send to the
//// owner (`Waking`): a game connection is told of the players that come into
//// range by the map's deliveries. What it selects is handled in the owner's
//// process, in order with what the socket reads, so the connection's state is
//// still its owner's alone.
////
//// A request of the shutdown coordinator to close ends the connection like a
//// client that leaves: the socket is closed, the line is logged and the owner
//// stops normally. A handler that is busy holds the request until it returns.
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
import genesis_prime/shutdown
import genesis_prime/telemetry/log.{type Who}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

/// How long the owner has to start, in milliseconds.
const start_deadline_ms = 5000

/// What a socket owner does with each frame when it only looks at them: the
/// game logic, given by whoever starts the listener. It runs in the socket
/// owner's process, so a slow handler holds the owner, and flow control keeps
/// the socket's reads waiting in the runtime meanwhile. `settings` makes a
/// frame-mode protocol of one that writes nothing.
pub type Handler =
  fn(Frame) -> Nil

/// How the owner reads the socket. In `Frames` mode the bytes are cut into
/// frames, each of which takes a token and is handed on, and a frame over the
/// size cap ends the connection. In `RawBytes` mode every read is handed on as
/// it came and takes a token, and the conversation bounds what it keeps.
pub type Mode {
  Frames
  RawBytes
}

/// What a conversation is handed: a whole frame in `Frames` mode, the bytes of
/// a read in `RawBytes` mode.
pub type Input {
  FrameRead(frame: Frame)
  BytesRead(bytes: BitArray)
}

/// What a conversation answers an input or a new connection with: the bytes
/// to write, in order; whether to close the socket after writing them; and the
/// conversation that handles the next input. A conversation that closes is not
/// asked again.
pub type Reaction {
  Reaction(send: List(BitArray), close: Bool, next: Conversation)
}

/// One connection's logic and its state, which lives in the function's
/// closure. It runs in the socket owner's process.
pub type Conversation {
  /// A conversation that answers what the socket reads.
  Conversation(handle: fn(Input) -> Reaction)
  /// A conversation that is also woken by messages other processes send to
  /// the owner, such as a map's deliveries. `wake` selects those messages,
  /// each mapped to the reaction the conversation makes of it; it is made with
  /// the conversation's own state, so each reaction's next conversation brings
  /// its own.
  Waking(handle: fn(Input) -> Reaction, wake: Selector(Reaction))
}

/// What a listener serves: the mode its sockets are read in, and the step that
/// runs when a client connects, given the client's peer address as text. The
/// step gives the first writes, such as a server's hello, and the
/// conversation the connection starts with.
pub type Protocol {
  Protocol(mode: Mode, connect: fn(Option(String)) -> Reaction)
}

/// What a socket owner needs to start.
pub type Settings {
  Settings(
    protocol: Protocol,
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
  /// The shutdown coordinator asked the connection to close.
  ServerStopping
  /// The socket reported something.
  SocketEvent(event: socket.Event)
  /// What a waking conversation's selector selected, already turned into the
  /// conversation's reaction.
  Woken(reaction: Reaction)
}

/// What the owner is doing: waiting for the acceptor to give it the socket,
/// or reading it with the connection's conversation.
type Status {
  AwaitingSocket
  Reading(reader: Reader, conversation: Conversation)
}

/// What the owner keeps of the bytes it read, by mode: the start of a frame
/// that has not fully arrived and the rate bucket, or the bucket alone.
type Reader {
  FrameReader(inbound: Inbound)
  RawReader(bucket: rate_limit.Bucket)
}

type State {
  State(
    settings: Settings,
    self: Subject(Message),
    socket: Socket,
    who: Who,
    status: Status,
    waking: Bool,
  )
}

/// Who the socket owner's lines are from: the process, by its name, and the
/// client's peer address. A connection has no account until it logs in, so
/// its peer is the only name of its client.
fn owner_who(peer: Option(String)) -> Who {
  log.Who(
    account: None,
    actor: None,
    place: Some(log.Process("socket_owner")),
    message: None,
    peer:,
  )
}

/// The reads the runtime hands an owner before it asks for more: 32. At 800
/// connections each sending 120 frames a second, a server's CPU time was
/// 1.092 cores with `ActiveOnce`, 0.948 with 8 reads and 0.868 with 32, the
/// median of 5 rounds, every round of 32 below every round of once; the
/// longest mailbox read was 1, 2 and 2 messages. 32 saves 0.224 of a core,
/// above the 0.05 that makes a mode worth its larger mailbox bound.
const reads_per_arm = 32

/// Settings with the limits the server measured: `reads_per_arm` reads at a
/// time, the client's rate and the heap ceiling, reading the monotonic clock,
/// for a frame-mode protocol that only hands each frame to `handler` and writes
/// nothing.
pub fn settings(handler handler: Handler) -> Settings {
  protocol_settings(protocol: observing(handler))
}

/// The frame-mode protocol of a handler that only looks at frames.
fn observing(handler: Handler) -> Protocol {
  Protocol(mode: Frames, connect: fn(_peer) {
    Reaction(send: [], close: False, next: observer(handler))
  })
}

fn observer(handler: Handler) -> Conversation {
  Conversation(handle: fn(input) {
    case input {
      FrameRead(frame:) -> handler(frame)
      BytesRead(..) -> Nil
    }
    Reaction(send: [], close: False, next: observer(handler))
  })
}

/// Settings with the measured limits for a protocol.
pub fn protocol_settings(protocol protocol: Protocol) -> Settings {
  Settings(
    protocol:,
    flow_control: socket.ActiveCount(reads: reads_per_arm),
    rate: rate_limit.client_rate(),
    heap_ceiling_words: capacity.heap_ceiling_words(),
    clock: clock.monotonic_milliseconds,
  )
}

/// Starts the owner of `socket`. It sets its heap ceiling first, counting
/// shared binaries, registers with the shutdown coordinator as a connection,
/// whose request to close ends the owner after it closes the socket, and starts
/// reading only after `socket_given`.
pub fn start(
  settings settings: Settings,
  socket socket: Socket,
  shutdown shutdown: shutdown.Settings,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_ms, fn(subject) {
    limit_heap(settings.heap_ceiling_words, True)
    keep_messages_off_heap()
    shutdown.register(
      settings: shutdown,
      participant: shutdown.Connection(close: fn() {
        process.send(subject, ServerStopping)
      }),
    )
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> socket.select(SocketEvent)
    let state =
      State(
        settings:,
        self: subject,
        socket:,
        who: owner_who(socket.peer(socket)),
        status: AwaitingSocket,
        waking: False,
      )
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
    SocketGiven, AwaitingSocket -> connect(state)
    SocketGiven, Reading(..) -> actor.continue(state)
    ServerStopping, _ ->
      end_connection(state, log.info, "the server is stopping")
    SocketEvent(socket.Received(bytes:)), Reading(reader:, conversation:) ->
      receive(state:, reader:, conversation:, bytes:)
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
    Woken(reaction:), Reading(..) -> carry_out(state, reaction, settle)
    Woken(..), AwaitingSocket ->
      actor.stop_abnormal("a conversation woke before the owner had one")
  }
}

/// Runs the protocol's connect step for the client that connected, carries out
/// its reaction and starts reading in the protocol's mode.
fn connect(state: State) -> actor.Next(State, Message) {
  let protocol = state.settings.protocol
  let reaction = protocol.connect(socket.peer(state.socket))
  let now = state.settings.clock()
  let reader = case protocol.mode {
    Frames ->
      FrameReader(inbound.new(rate: state.settings.rate, now_milliseconds: now))
    RawBytes ->
      RawReader(rate_limit.new(rate: state.settings.rate, now_milliseconds: now))
  }
  carry_out(
    State(..state, status: Reading(reader:, conversation: reaction.next)),
    reaction,
    arm,
  )
}

/// Writes what a reaction sends, in order, then closes the socket when the
/// reaction says to, and otherwise goes on with `then`, with the reaction's
/// conversation in place. A write that fails ends the connection.
fn carry_out(
  state: State,
  reaction: Reaction,
  then: fn(State) -> actor.Next(State, Message),
) -> actor.Next(State, Message) {
  case write_all(state.socket, reaction.send) {
    Error(reason) ->
      end_connection(
        state,
        log.warning,
        "the socket failed writing: " <> socket.describe(reason),
      )
    Ok(Nil) ->
      case reaction.close {
        True ->
          end_connection(state, log.info, "the connection's logic closed it")
        False -> then(with_conversation(state, reaction.next))
      }
  }
}

fn write_all(
  socket: Socket,
  writes: List(BitArray),
) -> Result(Nil, socket.Reason) {
  case writes {
    [] -> Ok(Nil)
    [bytes, ..rest] ->
      case socket.send(socket, bytes) {
        Ok(Nil) -> write_all(socket, rest)
        Error(reason) -> Error(reason)
      }
  }
}

fn with_conversation(state: State, conversation: Conversation) -> State {
  case state.status {
    Reading(reader:, ..) ->
      State(..state, status: Reading(reader:, conversation:))
    AwaitingSocket -> state
  }
}

/// Hands what the socket read to the connection's conversation, in the
/// protocol's mode, writes what it sends and asks the socket for more, unless
/// a limit ended the connection or the conversation closed it.
fn receive(
  state state: State,
  reader reader: Reader,
  conversation conversation: Conversation,
  bytes bytes: BitArray,
) -> actor.Next(State, Message) {
  case reader {
    FrameReader(inbound:) -> {
      let #(inbound, effects) =
        inbound.receive(
          inbound:,
          received: bytes,
          now_milliseconds: state.settings.clock(),
        )
      deliver(
        State(
          ..state,
          status: Reading(reader: FrameReader(inbound:), conversation:),
        ),
        effects,
      )
    }
    RawReader(bucket:) ->
      case rate_limit.take(bucket:, now_milliseconds: state.settings.clock()) {
        Error(exceeded) ->
          end_connection(
            state,
            log.warning,
            inbound.describe(reason: inbound.TooFast(exceeded:)),
          )
        Ok(bucket) -> {
          let state =
            State(
              ..state,
              status: Reading(reader: RawReader(bucket:), conversation:),
            )
          carry_out(state, conversation.handle(BytesRead(bytes:)), next_reads)
        }
      }
  }
}

/// Hands each frame the inbound rule delivered to the conversation, in order,
/// and ends the connection at the rule's `End` effect, after the frames before
/// it.
fn deliver(
  state: State,
  effects: List(inbound.Effect),
) -> actor.Next(State, Message) {
  case effects, state.status {
    [], _ -> next_reads(state)
    [inbound.End(reason:), ..], _ ->
      end_connection(state, log.warning, inbound.describe(reason:))
    [inbound.Deliver(frame:), ..rest], Reading(conversation:, ..) ->
      carry_out(state, conversation.handle(FrameRead(frame:)), fn(state) {
        deliver(state, rest)
      })
    [_, ..], AwaitingSocket -> actor.continue(state)
  }
}

/// Asks for the next read once the owner has taken what it was given: at once
/// in `ActiveOnce`, and when the runtime says the reads are used up
/// otherwise.
fn next_reads(state: State) -> actor.Next(State, Message) {
  case state.settings.flow_control {
    socket.ActiveOnce -> arm(state)
    socket.ActiveCount(..) -> settle(state)
  }
}

/// Goes on with the conversation the state holds: when it is woken by other
/// processes, the owner selects what it selects as well as the socket and its
/// own messages, and a conversation that is not goes back to the base
/// selector. The selector is made again each time because each reaction brings
/// a conversation with its own state, and its selector maps what it selects
/// with that state.
fn settle(state: State) -> actor.Next(State, Message) {
  case state.status {
    Reading(conversation: Waking(wake:, ..), ..) ->
      actor.continue(State(..state, waking: True))
      |> actor.with_selector(selector(state:, wake: Some(wake)))
    Reading(conversation: Conversation(..), ..) | AwaitingSocket ->
      case state.waking {
        True ->
          actor.continue(State(..state, waking: False))
          |> actor.with_selector(selector(state:, wake: None))
        False -> actor.continue(state)
      }
  }
}

/// What the owner selects: its own messages, the socket's events and, for a
/// woken conversation, what it selects.
fn selector(
  state state: State,
  wake wake: Option(Selector(Reaction)),
) -> Selector(Message) {
  let base =
    process.new_selector()
    |> process.select(state.self)
    |> socket.select(SocketEvent)
  case wake {
    Some(wake) ->
      process.merge_selector(base, process.map_selector(wake, Woken))
    None -> base
  }
}

/// Asks the socket for the next reads in the owner's flow control.
fn arm(state: State) -> actor.Next(State, Message) {
  case socket.arm(state.socket, state.settings.flow_control) {
    Ok(Nil) -> settle(state)
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
  write(state.who, "connection ended: " <> why)
  actor.stop()
}

/// Sets the calling process's heap ceiling in words, killing it when it needs
/// more, shared binaries counted, and logging the kill.
@external(erlang, "heap_limit_ffi", "limit")
fn limit_heap(words: Int, include_shared_binaries: Bool) -> Nil

/// Keeps the calling process's waiting messages off its heap.
@external(erlang, "genesis_prime_socket_ffi", "keep_messages_off_heap")
fn keep_messages_off_heap() -> Nil
