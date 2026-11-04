//// The contract between a process's rule and its shell. A rule is a pure
//// function `step(state, input) -> #(state, Step)`: it takes one input and
//// returns its new state and what its shell must carry out. The shell turns
//// everything that reaches its process into an input, carries out the effects
//// in order and decides nothing, so every decision is the rule's, and a
//// connection's recorded session (genesis_prime/wire_recording) replays them
//// through the real server.
////
//// There are two kinds of process, each with its own shell: a connection
//// (genesis_prime/connection/shell), which owns a client socket, and a service
//// (genesis_prime/service/shell), which other processes ask. `Event` and
//// `Effect` hold only what both shells give and carry out: the end of a
//// watch, the server stopping, opening and closing a watch, a log line and
//// the end of the process. Everything only one shell gives or carries out is
//// in that kind's own type, which comes in through `OwnEvent` and `OwnEffect`:
//// - a connection: `ConnectionEvent(message, answer)` in (its socket, a
////   message sent to it, a timer, the outcome of its ask) and
////   `ConnectionEffect` out (a write, a timer, a tell);
//// - a service: `ServiceEvent(message)` in (its start, an ask, a tell) and
////   `ServiceEffect(outgoing)` out (a reply, a send).
//// A shell is handed only its kind's types, so a rule that returns an effect
//// its shell does not carry out, or takes an input its shell never gives, does
//// not compile. The rule's own types are:
//// - `message`: what another process sends or asks it;
//// - `outgoing`: what a service sends another process without waiting, and
////   the answers it gives to asks; a send names its receiver in the effect
////   (`Send(to, message)`), not in the message;
//// - `request`: what a connection asks another process, each value naming the
////   process it asks; a service makes no ask, so its request type, `NoAsk`,
////   has no values;
//// - `answer`: what comes back from a connection's asks.
////
//// No value here holds a function, a process id, a monitor or a subject:
//// other processes are named by `Address`, watches, timers and asks by ids
//// the rule chooses, and a process that asks this one by an id the shell
//// chooses.

import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/spawn_id.{type SpawnId}
import gleam/option.{type Option, None}

/// A rule as its shell runs it. `name` is the rule's module path, which a
/// connection's wire recording names in its header, and `settings` are made
/// once at start. This is the shell's view of a rule, so it holds functions; no
/// type a rule takes or returns does. `own_input` and `own_effect` are the
/// kind's own types, which `ConnectionRule` and `ServiceRule` fix.
pub type Rule(settings, state, request, own_input, own_effect) {
  Rule(
    name: String,
    settings: settings,
    new: fn(settings) -> state,
    step: fn(state, Input(own_input)) -> #(state, Step(request, own_effect)),
  )
}

/// A connection's rule: the one kind with a socket. The connection shell runs
/// only this kind.
pub type ConnectionRule(settings, state, request, message, answer) =
  Rule(
    settings,
    state,
    request,
    ConnectionEvent(message, answer),
    ConnectionEffect(request),
  )

/// An input to a connection's rule.
pub type ConnectionInput(message, answer) =
  Input(ConnectionEvent(message, answer))

/// What a connection's rule returns.
pub type ConnectionStep(request) =
  Step(request, ConnectionEffect(request))

/// A service's rule: the one kind other processes ask. It makes no ask, so its
/// request type is `NoAsk`. The service shell runs only this kind.
pub type ServiceRule(settings, state, message, outgoing) =
  Rule(settings, state, NoAsk, ServiceEvent(message), ServiceEffect(outgoing))

/// An input to a service's rule.
pub type ServiceInput(message) =
  Input(ServiceEvent(message))

/// What a service's rule returns.
pub type ServiceStep(outgoing) =
  Step(NoAsk, ServiceEffect(outgoing))

/// The request type of a rule that makes no ask: it has no values, so such a
/// rule cannot build an `EffectsThenAsk`.
pub type NoAsk

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

/// One input to a rule: what happened, and when. `own` is the kind's own
/// input type, `ConnectionEvent` or `ServiceEvent`.
pub type Input(own) {
  Input(now: Now, event: Event(own))
}

/// What happened to the process: what both kinds of process take, or, in
/// `OwnEvent`, what only its kind takes.
pub type Event(own) {
  /// What only this kind of process takes.
  OwnEvent(event: own)
  /// A process the rule watched ended, or was not running when the watch
  /// began.
  WatchEnded(watch: WatchId)
  /// The server is stopping. The process has until `deadline_ms` on the
  /// monotonic clock to finish, and is then stopped whatever its state.
  Stopping(deadline_ms: Int)
}

/// What only a service takes.
pub type ServiceEvent(message) {
  /// A service started. It is the first input of a service.
  Started
  /// A timer the rule started with `StartServiceTimer` fired. A timer that was
  /// cancelled gives none.
  ServiceTimerFired(timer: TimerId)
  /// The creature a `StartCreature` named under `watch` was not started: the
  /// reason as the creature supervisor reported it, for the rule's log line. The
  /// watch was never opened, so no `WatchEnded` follows for it.
  CreatureNotStarted(watch: WatchId, reason: String)
  /// Another process asked the process something; the rule answers it once,
  /// with `Reply`.
  Asked(caller: CallerId, message: message)
  /// Another process told the process something with no answer expected (a
  /// connection's `Tell` effect); the rule replies to no one, and a rule that
  /// gets a message in the form it takes only as an ask, or the reverse, has a
  /// bug.
  Told(message: message)
}

/// What only a connection takes: what happened to its socket, what reached it
/// from other processes, and what it waited for.
pub type ConnectionEvent(message, answer) {
  /// The connection's socket is the process's own. It is the first input of a
  /// connection. `seed` is 32 bytes from the operating system's strong random
  /// source, drawn once for the connection; every random value the rule needs
  /// comes from it (genesis_prime/random), so a recording replays them.
  Accepted(connection: ConnectionId, peer: Peer, seed: BitArray)
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
  /// Another process sent the connection a message.
  Woken(message: message)
  /// A timer the rule started fired.
  TimerFired(timer: TimerId)
  /// The outcome of the ask that ended the rule's last step.
  Answered(ask: AskId, outcome: Outcome(answer))
}

/// Why a socket operation failed.
pub type SocketFailure {
  /// The socket was already closed: a write to a socket the peer has closed
  /// fails as closed, and so does arming the read of one (the shell's Erlang
  /// file reports the `einval` that answers). It ends a connection as the
  /// peer's close does.
  Closed
  /// The peer reset the connection.
  Reset
  /// A write did not finish within the socket's send deadline.
  SendTimedOut
  /// Any other reason, as the socket reported it.
  OtherSocketFailure(reason: String)
}

/// A sentence that says why a socket operation failed, for the log.
pub fn describe_socket_failure(failure failure: SocketFailure) -> String {
  case failure {
    Closed -> "the socket was closed"
    Reset -> "the peer reset the connection"
    SendTimedOut -> "the write timed out"
    OtherSocketFailure(reason:) -> reason
  }
}

/// The address and port the client connected from, for logs before login.
pub type Peer {
  Peer(address: String, port: Int)
}

/// What the shell does after the rule's step.
pub type Step(request, own) {
  /// Carry out the effects in order, then take the next input.
  Effects(effects: List(Effect(own)))
  /// Carry out the effects in order, then make the ask, and take no other
  /// input until its outcome comes back as `Answered`. Work the rule had not
  /// finished, such as the rest of a read's frames, stays in its state. A
  /// rule whose request type is `NoAsk` cannot build it.
  EffectsThenAsk(effects: List(Effect(own)), ask: Ask(request))
}

/// One thing the shell carries out: what both kinds of process carry out, or,
/// in `OwnEffect`, what only its kind does.
pub type Effect(own) {
  /// What only this kind of process carries out.
  OwnEffect(effect: own)
  /// Start watching a process. Its end comes back as `WatchEnded`, once.
  Watch(watch: WatchId, target: Address)
  /// Stop watching. A `WatchEnded` for it already waiting is dropped.
  Unwatch(watch: WatchId)
  /// Write a log line through Erlang's logger.
  Log(line: LogLine)
  /// End the process normally once the step's other effects are carried
  /// out; a connection closes its socket first.
  Stop
}

/// What only a connection carries out. `request` is what the rule asks or
/// tells another process (the rule's request type).
pub type ConnectionEffect(request) {
  /// Write bytes to the connection's socket. A failed write stops the step's
  /// remaining effects and comes back as `WriteFailed`.
  Write(bytes: BitArray)
  /// Start a timer. Its firing comes back as `TimerFired`, once.
  StartTimer(timer: TimerId, after_ms: Int)
  /// Cancel a timer. A `TimerFired` for it already waiting is dropped.
  CancelTimer(timer: TimerId)
  /// Tell the process at `to` something and go on at once: nothing waits for
  /// an answer, no deadline runs and no outcome comes back. The shell tells
  /// through the way to `to` that the rule's open watch on `to` found, so the
  /// rule watches `to` before it tells; a tell with no such watch, or after the
  /// process has ended, is dropped with a warning, and a rule that must know
  /// watches it. A `Connection` and a `ZoneChannel` need no watch: the shell
  /// sends the tell through the registry, to the connection or to every member
  /// of the group. The process takes it as `ServiceEvent`'s `Told`.
  Tell(to: Address, request: request)
  /// Tell the process that the open watch `watch` found, through that watch's
  /// own way to tell it (`Tellable`), and go on at once, as `Tell` does. It is
  /// dropped with no line when the watch found no process or is no longer open:
  /// the rule learns that from the watch's end, so a whisper to an offline name
  /// logs nothing. A tell by address would use any open watch on the address,
  /// which can be a watch on a connection that is ending.
  TellWatched(watch: WatchId, request: request)
  /// Make this connection's process a member of the registry's group at
  /// `address`, which only a `CharacterNamed` or a `ZoneChannel` names. The
  /// group holds the process until it leaves it or ends: the registry notices
  /// an end by itself, so a connection that crashes leaves every group it
  /// joined.
  JoinGroup(address: Address)
  /// Remove this connection's process from the group at `address`; nothing
  /// happens when it is not a member.
  LeaveGroup(address: Address)
}

/// What only a service carries out.
pub type ServiceEffect(outgoing) {
  /// Answer an ask. An answer to a caller that has ended or stopped waiting
  /// is dropped.
  Reply(caller: CallerId, answer: outgoing)
  /// Send the process at `to` a message without waiting. The shell finds the
  /// process from the address (a connection or a creature through OTP's `pg`,
  /// by its id); a receiver that is not running drops the message, and a rule
  /// that must know watches the receiver.
  Send(to: Address, message: outgoing)
  /// Start the creature the value describes under the creature supervisor, wait
  /// for it to be running, then watch it under `watch`, so the step's later
  /// effects (a `Send` to its `Creature` address) find it and its end comes back
  /// as `WatchEnded`. A creature that does not start comes back as
  /// `CreatureNotStarted`, with no watch opened.
  StartCreature(watch: WatchId, creature: CreatureStart)
  /// Start a timer. Its firing comes back as `ServiceTimerFired`, once.
  StartServiceTimer(timer: TimerId, after_ms: Int)
  /// Cancel a timer. A `ServiceTimerFired` for it already waiting is dropped.
  CancelServiceTimer(timer: TimerId)
}

/// A creature a map has its supervisor start: which creature of the map's
/// run it is, the spawn it stands at and the clock it stamps its 0x262 from. The creature's rule and its process are
/// `genesis_prime/world_map/creature`; this is the rule's start settings, with
/// no process in it.
pub type CreatureStart {
  CreatureStart(
    /// The map the creature stands in.
    map: MapId,
    /// The run of that map the creature belongs to: it ends with the run.
    incarnation: Int,
    /// The creature's unit id in its run: its spawn's own, from the map's counter
    /// when the spawn first has a creature, and kept while the creature stops
    /// cleanly.
    unit_id: Int,
    /// The creature's life: the number of the watch the map opens on it, unique in
    /// the run, so the address `Creature(map, incarnation, unit_id, life)` is
    /// one creature process and no other.
    life: Int,
    /// The spawn it stands at (genesis_prime/world_map/spawn), by its id.
    spawn_id: SpawnId,
    /// The monotonic time the map's clock started at, from which the creature
    /// stamps its 0x262 (genesis_prime/world_map/map `server_time`).
    clock_origin_ms: Int,
  )
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
  /// the asked process acted; an answer after it gives the rule no input.
  NoAnswerInTime
  /// The asked process ended before it answered.
  EndedBeforeAnswer
  /// The server began stopping, so the shell stopped waiting; `Stopping`
  /// follows once a step ends without an ask. Nothing is known about whether
  /// the asked process acted; an answer after it gives the rule no input.
  StoppedWaiting
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
  /// One map, in the one run of it that started with `incarnation`
  /// (genesis_prime/world_map/registry): a map that ends and is started again
  /// is another address, so a watch never lands on a copy that never held
  /// the watcher's player.
  Map(map: MapId, incarnation: Int)
  /// One connection.
  Connection(connection: ConnectionId)
  /// One creature, in one run of one map: its unit id there and its life, the
  /// number of the map's watch it was started under. A spawn's unit id is kept
  /// across a clean stop, so the unit id alone names the stopped creature and
  /// the one started in its place; the life tells them apart, so a watch or a
  /// send never lands on a replacement and no two members of one group exist
  /// (genesis_prime/world_map/creature_registry).
  Creature(map: MapId, incarnation: Int, unit_id: Int, life: Int)
  /// The one connection whose player is in the world under this name, folded
  /// to lower case (genesis_prime/game/chat): a group of the connections'
  /// registry (genesis_prime/connection/registry) that the connection joins as
  /// its player enters the world and leaves as it camps. A whisper is told to
  /// it through a watch, as a tell to a map run is, so a name no connection
  /// holds ends the watch.
  CharacterNamed(folded_name: String)
  /// The connections whose players are in this run of this map under this top
  /// zone (genesis_prime/game/top_zone): a group of the connections' registry
  /// that each connection joins and leaves by its own effects. A tell to it
  /// goes to every member, and needs no watch.
  ZoneChannel(map: MapId, incarnation: Int, top_zone_id: Int)
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

/// What a log line is about when it is about no one in particular.
pub const no_one =
  About(
    connection: None,
    peer: None,
    account_id: None,
    character_id: None,
    map: None,
    message: None,
  )

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
