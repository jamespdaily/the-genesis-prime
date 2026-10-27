//// The contract between a process's rule and its shell. A rule is a pure
//// function `step(state, input) -> #(state, Step)`: it takes one input and
//// returns its new state and what its shell must carry out. The shell turns
//// everything that reaches its process into an input, carries out the effects
//// in order and decides nothing, so the inputs a process took replay its every
//// decision with no other process, socket, clock or database.
////
//// Each rule fills in the type parameters with its own types:
//// - `message`: what another process sends or asks it;
//// - `outgoing`: what it sends another process without waiting, each value
////   naming its receiver, and the answers it gives to asks;
//// - `request`: what it asks another process, each value naming the process
////   it asks;
//// - `answer`: what comes back from its asks.
////
//// No value here holds a function, a process id, a monitor or a subject:
//// other processes are named by `Address`, watches, timers and asks by ids
//// the rule chooses, and a process that asks this one by an id the shell
//// chooses.

import genesis_prime/world_map/map_id.{type MapId}
import gleam/option.{type Option}

/// The time an input reached the shell, read once as the shell takes it, so
/// every part of one step reads the same time.
pub type Now {
  Now(
    /// Milliseconds on the monotonic clock, for deadlines, rate limits and
    /// the frame cut. It can be negative, so 0 never means none.
    monotonic_ms: Int,
    /// The system time as a Windows FILETIME, 100-nanosecond intervals since
    /// 1601, the form the client's messages carry the server's time in
    /// (opcode.0x117).
    filetime: Int,
  )
}

/// One input to a rule: what happened, and when.
pub type Input(message, answer) {
  Input(now: Now, event: Event(message, answer))
}

/// What happened to the process.
pub type Event(message, answer) {
  /// A process with no socket started. It is the first input of such a
  /// process.
  Started
  /// The connection's socket. `Accepted` is the first input of a connection.
  Socket(event: SocketEvent)
  /// Another process sent the process a message.
  Woken(message: message)
  /// Another process asked the process something; the rule answers it once,
  /// with `Reply`.
  Asked(caller: CallerId, message: message)
  /// A process the rule watched ended, or was not running when the watch
  /// began.
  WatchEnded(watch: WatchId)
  /// A timer the rule started fired.
  TimerFired(timer: TimerId)
  /// The outcome of the ask that ended the rule's last step.
  Answered(ask: AskId, outcome: Outcome(answer))
  /// An answer to an ask whose outcome was already `NoAnswerInTime`.
  AnsweredLate(ask: AskId)
  /// The server is stopping. The process has until `deadline_ms` on the
  /// monotonic clock to finish, and is then stopped whatever its state.
  Stopping(deadline_ms: Int)
}

/// What happened to a connection's socket.
pub type SocketEvent {
  /// The connection's socket is the process's own.
  Accepted(connection: ConnectionId, peer: Peer)
  /// Bytes arrived, in the order the socket received them; a read may hold
  /// part of a frame or several frames.
  Read(bytes: BitArray)
  /// The client closed the connection.
  PeerClosed
  /// Reading from the socket failed.
  ReadFailed(failure: SocketFailure)
  /// A write of the last step failed. The shell carried out none of that
  /// step's effects after the failed write.
  WriteFailed(failure: SocketFailure)
}

/// Why a socket operation failed.
pub type SocketFailure {
  /// The socket was already closed.
  Closed
  /// The peer reset the connection.
  Reset
  /// A write did not finish within the socket's send deadline.
  SendTimedOut
  /// Any other reason, as the socket reported it.
  OtherSocketFailure(reason: String)
}

/// The address and port the client connected from, for logs before login.
pub type Peer {
  Peer(address: String, port: Int)
}

/// What the shell does after the rule's step.
pub type Step(outgoing, request) {
  /// Carry out the effects in order, then take the next input.
  Effects(effects: List(Effect(outgoing)))
  /// Carry out the effects in order, then make the ask, and take no other
  /// input until its outcome comes back as `Answered`. Work the rule had not
  /// finished, such as the rest of a read's frames, stays in its state.
  EffectsThenAsk(effects: List(Effect(outgoing)), ask: Ask(request))
}

/// One thing the shell carries out.
pub type Effect(outgoing) {
  /// Write bytes to the connection's socket. A failed write stops the step's
  /// remaining effects and comes back as `WriteFailed`.
  Write(bytes: BitArray)
  /// Send another process a message without waiting. A receiver that is not
  /// running drops it; a rule that must know watches the receiver.
  Send(message: outgoing)
  /// Answer an ask. An answer to a caller that has ended or stopped waiting
  /// is dropped.
  Reply(caller: CallerId, answer: outgoing)
  /// Start watching a process. Its end comes back as `WatchEnded`, once.
  Watch(watch: WatchId, target: Address)
  /// Stop watching. A `WatchEnded` for it already waiting is dropped.
  Unwatch(watch: WatchId)
  /// Start a timer. Its firing comes back as `TimerFired`, once.
  StartTimer(timer: TimerId, after_ms: Int)
  /// Cancel a timer. A `TimerFired` for it already waiting is dropped.
  CancelTimer(timer: TimerId)
  /// Write a log line through Erlang's logger.
  Log(line: LogLine)
  /// End the process normally once the step's other effects are carried
  /// out; a connection closes its socket first.
  Stop
}

/// An ask of another process, answered once.
pub type Ask(request) {
  Ask(
    ask: AskId,
    request: request,
    /// The time on the monotonic clock after which the outcome is
    /// `NoAnswerInTime`.
    deadline_ms: Int,
  )
}

/// How an ask ended.
pub type Outcome(answer) {
  /// The process answered before the deadline.
  Answer(answer: answer)
  /// No process was running at the asked address; nothing was sent.
  NotRunning
  /// No answer came before the deadline. Nothing is known about whether
  /// the asked process acted; an answer after it comes as `AnsweredLate`.
  NoAnswerInTime
  /// The asked process ended before it answered.
  EndedBeforeAnswer
}

/// A process another process can watch, named by its role or its id.
pub type Address {
  /// The registry of who is logged in, one slot per account.
  Sessions
  /// The one-time keys a client carries from one server to the next.
  HandOff
  /// The workers that read and write the database.
  Store
  /// The registry that starts and finds maps.
  Maps
  /// One map.
  Map(map: MapId)
  /// One connection.
  Connection(connection: ConnectionId)
}

/// One connection, unique for the node's life; the shell picks it when it
/// accepts the connection.
pub type ConnectionId {
  ConnectionId(Int)
}

/// A process that asked this one, chosen by the shell when the ask arrives;
/// unique within the process's life.
pub type CallerId {
  CallerId(Int)
}

/// One watch, chosen by the rule; unique among the process's open watches.
pub type WatchId {
  WatchId(Int)
}

/// One timer, chosen by the rule; unique among the process's running timers.
pub type TimerId {
  TimerId(Int)
}

/// One ask, chosen by the rule; unique within the process's life, so a late
/// answer is never taken for a newer ask's.
pub type AskId {
  AskId(Int)
}

/// A log line, with the who and where it is about.
pub type LogLine {
  LogLine(level: LogLevel, text: String, about: About)
}

/// Who and where a log line is about, each written as its own logger
/// metadata key. A field is `None` until the process knows it. No field holds
/// a password, a session key or another secret.
pub type About {
  About(
    connection: Option(ConnectionId),
    /// Where the client connected from, for lines before login.
    peer: Option(Peer),
    account_id: Option(Int),
    character_id: Option(Int),
    map: Option(MapId),
    /// The client message the line is about: its name and its number.
    message: Option(#(String, Int)),
  )
}

/// How much a log line matters.
pub type LogLevel {
  /// A bug, always looked into.
  LogError
  /// An outside failure the server recovered from.
  LogWarning
  /// Start, stop, login and logout.
  LogInfo
  /// Detail of each message, off by default.
  LogDebug
}
