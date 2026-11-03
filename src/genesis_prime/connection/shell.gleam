//// The shell of a connection: the process that owns one client socket and
//// runs one rule over it, a gleam_otp actor that Ranch starts. It turns
//// everything that reaches the process into the rule's inputs, carries out the
//// rule's effects in order and decides nothing, so what crosses its socket
//// replays every decision (genesis_prime/wire_recording).
////
//// One connection, from accept to end:
////
//// ```
//// Ranch accepts ─▶ genesis_prime_connection_shell_ffi:start_link ─▶ start: the actor
////   initialiser: waiting messages off the heap, Begin sent to itself,
////     returns at once; Ranch then sends the handshake
////   Begin ─▶ ranch:handshake, the socket's options, exits trapped, the logger
////     metadata of the process (connection, peer)
////   the settings' `scripts` hands the connection its script (seed, clock,
////     scheduler) and its accept ordinal; the wire recorder, when on, opens its
////     file and writes the header
////   the registry, when the settings hold one: the shell joins the group of
////     Connection(id), so other processes find it (genesis_prime/connection/registry)
////   OwnEvent(Accepted(connection id, peer, seed)) ─▶ step ─▶ effects
////   after each step's effects, before the mailbox is read or a stop is taken:
////     a watch of a target no process holds ─▶ WatchEnded(id) ─▶ step ─▶ effects
////   loop, the socket active once, each message taken by the actor's selector:
////     {tcp, bytes}        ─▶ OwnEvent(Read(bytes))  ─▶ step ─▶ effects
////     {woken, message}    ─▶ OwnEvent(Woken(message)) ─▶ step ─▶ effects
////     a timer's message   ─▶ OwnEvent(TimerFired(id)) ─▶ step ─▶ effects
////     a watched process's DOWN ─▶ WatchEnded(id)   ─▶ step ─▶ effects
////     {tcp_closed}        ─▶ OwnEvent(PeerClosed)   ─▶ step ─▶ effects
////     {tcp_error, reason} ─▶ OwnEvent(ReadFailed(_)) ─▶ step ─▶ effects
////     the parent's exit   ─▶ Stopping(now + shutdown_ms) ─▶ step ─▶ effects
////   each input: the script's clock is called once, told its kind, for its `Now`; the wire
////     recorder writes the input's line before the step's effects, and each
////     write after the socket took it, with a sequence number taken before
//// ```
////
//// - **A handshake that fails.** A client gone before the handshake, or a
////   socket that cannot be set up, ends the connection normally with a debug
////   line and no warning or error: no recording was opened and no step ran.
//// - **Reads.** The socket's buffer is `frame.read_limit`, so no read holds
////   more bytes than that, and the socket is active once: the shell arms it
////   again after each step's effects, including while an ask waits. What
////   arrives meanwhile is the rule's to hold or refuse
////   (`genesis_prime/client_connection.hold`). In a replay the script gives
////   the byte count of the next recorded read, and the shell holds what arrives
////   and arms the socket again until it holds that many, so the recorded read
////   is one input (`read_arrived`).
//// - **A message the selector does not take.** The shell drops it and logs a
////   warning that names the message's kind (its tag or its shape) and never its
////   contents, which could hold a secret; the line carries the connection's
////   metadata.
//// - **Exits.** The shell traps exits once it holds the socket, so before the
////   handshake the parent's stop ends it, with no recording to close. After
////   it, the parent's exit is the rule's `Stopping` and another process's exit
////   is dropped.
//// - **Time.** Each input carries one `Now`: the monotonic clock in
////   milliseconds and the system time as a FILETIME. The shell reads it from
////   its script's clock (the node's in the server, the recording's in a replay)
////   with one call as it takes the input, and makes no call for a message it
////   drops (a stale timer, a late answer, another process's exit, a stray
////   message), so the calls made are the inputs taken. The seed of `Accepted`
////   is the script's. The only other time the shell takes is the node's own
////   monotonic time for that input, from the script (`node_monotonic_ms`), for
////   the wait of an ask, which is real time whatever the clock says; in the
////   server it is the `Now`'s own reading, never a second read.
//// - **A failed write.** The step's later effects are not carried out; the
////   next input is `OwnEvent(WriteFailed(_))`. A write that does not finish
////   within the send deadline fails as `SendTimedOut` and closes the socket.
//// - **Stop.** The shell carries out the rest of the step's effects in order,
////   closes the socket, the wire recorder writes the closing line (the client
////   closed it when the shell took the socket's close, the server otherwise,
////   also when the rule asked before it stopped, so that the step that stops is
////   not the one that took the close), and the process ends
////   normally; a step with a `Stop` makes no ask, and a
////   failed write after the `Stop` is logged as a warning, closes the socket
////   and ends the process with no `WriteFailed` input. Bytes still queued
////   get the send deadline, in whole seconds, to go out before the close drops
////   them. A rule must return
////   `Stop` after `PeerClosed` or `ReadFailed`, since no other socket input
////   reaches the process then.
//// - **The server stopping.** The shell traps its parent's exit, so the
////   tree's stop arrives as `Stopping`, with a deadline of the listener's
////   shutdown time less the send deadline, counted from when the shell takes
////   the exit and not from when it arrived: an exit that waits behind a step
////   is counted from when it is taken, while Ranch counts from when it sent
////   the stop. A rule that has not stopped by whichever deadline comes first
////   is killed, and its recording has no closing line.
//// - **A crash.** When the rule's step crashes, the actor ends with that
////   reason; Ranch starts connection processes as temporary children, so
////   nothing restarts it and the listener goes on accepting. The socket closes
////   with the process, and its recording has no closing line, so it never
////   replays.
//// - **A recording that cannot be written.** The shell logs it, closes the
////   socket and ends the process before that step's effects, so no input is
////   carried out without its record; the recording has no closing line.
//// - **An ask.** A step that ends in `EffectsThenAsk` has its effects carried
////   out first; a failed write or a `Stop` among them means the ask is never
////   made. The shell then hands the request and a reply, tagged with a fresh
////   reference, to the settings' `directory`, and waits, taking no other
////   input, until the outcome:
////
//// ```
//// directory(request, the ask's deadline on the node's clock, reply)
////   Error(Nil)              ─▶ Answered(ask, NotRunning), nothing sent
////   Ok(NoReplyInTime)       ─▶ Answered(ask, NoAnswerInTime), nothing sent
////   Ok(ToService(pid))      ─▶ monitor pid, wait until the ask's deadline
////   Ok(ToWorker(pid))       ─▶ monitor pid, wait until the ask's deadline
//// waiting:
////   {ask answer, tag, a}    ─▶ Answered(ask, Answer(a))
////   the target's DOWN       ─▶ Answered(ask, EndedBeforeAnswer)
////   the deadline passes     ─▶ Answered(ask, NoAnswerInTime); a worker is
////                                ended (exit shutdown) first
////   the parent's exit       ─▶ Answered(ask, StoppedWaiting) at once, then
////                                Stopping(when the wait takes the exit
////                                         + shutdown_ms - send_deadline_ms)
//// after NoAnswerInTime or StoppedWaiting, the tag and the monitor are kept
////   until the target's answer or DOWN; between steps:
////   {ask answer, tag, _} of a kept tag ─▶ tag dropped, no input
////   the DOWN of a kept tag             ─▶ tag dropped, no input
////   an answer or DOWN of no kept tag   ─▶ dropped
//// ```
////
////   The wait is a selective receive inside the handler, and the answers
////   arrive on one subject the connection keeps, each tagged with its ask's
////   reference. An answer whose ask is answered drops the ask's monitor, with
////   the DOWN that may already wait, so no monitor stays on the target. While
////   the shell waits, a system message (`sys:get_state`) waits too, up to the
////   ask's deadline. The deadline is on the node's own monotonic clock, counted
////   once from the time the ask allows from the `Now` of the input whose step
////   made it, so a message that does not end the wait never puts it off, and
////   a replay, whose `Now`s come from a recording, waits no longer than the
////   recording's ask allowed (`real_deadline_ms`).
////
////   A step that follows `StoppedWaiting` and ends in another ask gets
////   `Answered(_, StoppedWaiting)` at once, with no call to the directory, so
////   every ask has one `Answered`; `Stopping` is the next input after a step
////   that ends without an ask. A worker answers late only when its answer left
////   before the shell's exit reached it. A late answer gives the rule no input,
////   whether it comes after `NoAnswerInTime` or after `StoppedWaiting`; one
////   that arrives during a later ask is taken by that ask's wait and dropped,
////   and never answers the later ask. The `Now` of `Answered` is read when the
////   outcome is known.
////   Bytes the client sent during the ask are read only after it, since the
////   socket is active once and is not re-armed while the shell waits.
//// - **The directory's own wait.** `directory` runs before the wait begins,
////   so the deadline does not bound it. A service is reached by a send, which
////   never waits. A worker is started by its supervisor's `start_child`, a
////   call with no timeout, but the worker's start does no work before it
////   returns, so the call waits only for the starts queued before it; a
////   supervisor that has stopped exits the call with `noproc`, which
////   `store/worker.ask` turns into `Error(Nil)`. When the directory returns
////   past the deadline, the outcome is `NoAnswerInTime` at once.
//// - **A tell.** A `Tell(to, request)` effect sends the request to the process
////   at `to` and the shell goes on at once: nothing waits, no monitor is kept,
////   and no outcome comes back. The way to the process is the one the rule's
////   open watch on `to` found with its lookup (`Tellable`), so a tell makes no
////   lookup and a move costs none; it goes with the watch, whether the rule
////   drops it or the process ends. A tell to an address with no such watch is
////   dropped with a warning. A tell to a `Connection` needs no watch: the
////   settings' `deliver` sends it through the registry, one lookup of the
////   group of the connection's id as any service's send makes, and a connection
////   that is gone drops it with no line. A tell to a `ZoneChannel` needs no watch
////   either: `deliver` sends it to every member of the group. A tell to a
////   `CharacterNamed` goes through a watch, as a tell to a map run does: the
////   lookup finds the one connection that holds the name, and a name no
////   connection holds ends the watch as any target no process holds.
//// - **A tell through a watch.** `TellWatched(watch, request)` tells the process
////   that watch found, through that watch's own way to tell it, and drops the
////   tell with no line when the watch found none or is closed: a whisper to a
////   name no connection holds ends its watch instead of logging a warning.
//// - **A group.** `JoinGroup(address)` makes the connection's process a member
////   of the registry's group at `address` (a `CharacterNamed` or a
////   `ZoneChannel`) and `LeaveGroup(address)` removes it
////   (`registry.join_group`, `registry.leave_group`), each in the order of the
////   step's effects; a connection that ends leaves its groups by itself, since
////   the registry notices it.
//// - **A message delivered.** Another process sends the connection's pid
////   `{woken, message}` (`registry.deliver`); the shell takes it between steps
////   as `OwnEvent(Woken(message))`, in the order it arrived among the socket's
////   reads. One that arrives during an ask waits until the ask's outcome and
////   the step it starts are done, like a read. A message for a connection that has ended is
////   dropped by the VM, and one that arrives after the shell began to stop is
////   dropped with the process. A connection with no registry in its settings is
////   joined to no group, so no process can send it anything.
//// - **A watch.** `Watch(id, target)` finds the target's pid, and the way to
////   tell it when the rule tells it, with one call of the settings' `locate`,
////   monitors it and keeps the monitor under `id`
////   (genesis_prime/step/watch). Its DOWN is taken between steps as
////   `WatchEnded(id)`, once, and the shell forgets the watch. A target no
////   process holds is monitored by nothing: the shell holds the id and takes
////   `WatchEnded(id)` as the next input once the step is done, and after the
////   outcome of an ask the step ends in, since no other input is taken
////   meanwhile; before the mailbox is read and before a stop that arrived
////   during an ask, with the ends of the step's other such watches in the
////   order opened. A step that stops the connection takes none. `Unwatch(id)`
////   drops the monitor and the DOWN already waiting, or an id held for a target
////   no process holds. A watch's DOWN that arrives during an ask waits like a
////   delivered message. An id already open, monitored or held, ends the
////   connection with an error log.
//// - **A timer.** `StartTimer(id, ms)` starts a timer through the script's
////   scheduler (the operating system's `process.send_after` in the server, a
////   timer the replay client fires at its line in a replay) that sends the
////   shell's timer subject `Elapsed(id, reference)`, kept under `id` with its
////   own reference. It is taken between steps as
////   `OwnEvent(TimerFired(id))`, once, and the shell forgets the timer; one
////   that fires during an ask waits like a delivered message. `CancelTimer(id)`
////   cancels it and forgets it, so no `TimerFired` follows: a message that
////   had fired or is in flight when it is cancelled is discarded on arrival,
////   as is any message whose reference is not the current timer's of that id,
////   so a cancelled timer's message never fires a restarted timer of the same
////   id. An id with no running timer is cancelled to nothing. An id already
////   running ends the connection with an error log.
//// - **The registry's scope ending.** The connection stays joined only as long
////   as the scope lives; the tree restarts the game listener with the scope, so
////   no connection outlives it (genesis_prime/connection/registry).
//// - **Effects and inputs of the other kind.** A connection's own effects are
////   `Write`, `StartTimer`, `CancelTimer` and `Tell`, and its own inputs are the
////   socket's, `Woken`, `TimerFired` and `Answered` (`ConnectionEffect` and
////   `ConnectionEvent`). It has no `Reply`, `Send` or `Started`, so a rule that
////   answers a caller, sends, or takes a service's input does not compile
////   against this shell.

import genesis_prime/connection/frame
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/connection/script.{
  type Cancel, type Elapsed, type Issued, type Script, type Scripts,
}
import genesis_prime/seed
import genesis_prime/service.{type Sent}
import genesis_prime/step.{
  type Ask, type ConnectionEffect, type ConnectionEvent, type ConnectionId,
  type ConnectionRule, type Effect, type Event, type SocketFailure, type TimerId,
  Accepted, Answer, Answered, CancelTimer, ConnectionId, Effects, EffectsThenAsk,
  EndedBeforeAnswer, Input, LogDebug, LogError, LogWarning, NoAnswerInTime,
  NotRunning, OwnEffect, OwnEvent, ReadFailed, StartTimer, StoppedWaiting,
  Stopping, Write, WriteFailed,
}
import genesis_prime/step/runtime
import genesis_prime/step/watch.{type Watches}
import genesis_prime/wire_recording.{type Side}
import genesis_prime/wire_recording/recorder.{
  type WireRecorder, type WireWriter, type WriteError,
}
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Monitor, type Pid, type Selector, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

/// What every connection of one listener is started with.
pub type Settings(settings, state, message, answer, request) {
  Settings(
    rule: ConnectionRule(settings, state, request, message, answer),
    /// How long a write may wait for the socket before it fails as
    /// `SendTimedOut`.
    send_deadline_ms: Int,
    /// How long a connection has to stop once the server stops.
    shutdown_ms: Int,
    /// Where the bytes of each connection's socket reads and writes are
    /// recorded, a line after each (genesis_prime/wire_recording); `None`
    /// unless the dev start turns recording on.
    wire_recorder: Option(WireRecorder),
    /// Hands each connection, once the shell holds its socket, its own script:
    /// its seed, the clock that gives each input its `Now` and the scheduler
    /// its timers start through (genesis_prime/connection/script). The server's
    /// is `script.operating_system`; a replay's gives each connection the
    /// script of its recording.
    scripts: Scripts,
    /// How the shell reaches the process a request names: it sends the
    /// request with `reply` and says where it went, or `Error(Nil)` when that
    /// process is not running. Made once at start from the services' names,
    /// with `service.call` and `store/worker.ask`; a rule never sees it.
    directory: fn(request, Int, fn(answer) -> Nil) -> Result(Sent, Nil),
    /// Where each connection joins as it is accepted, so other processes
    /// find it by its id; `None` for a connection no process addresses (the
    /// login's).
    registry: Option(Registry(message)),
    /// How the shell finds the process a `Watch` names, with, for a process a
    /// rule tells, the way to tell it (`Tellable`: a function that sends it a
    /// request with no answer), from one lookup; `Error(Nil)` when it is not
    /// running or the lookup got no reply. Made once at start from the
    /// processes' names; a rule never sees it.
    locate: fn(step.Address) -> Result(watch.Found(fn(request) -> Nil), Nil),
    /// How the shell sends a request to the connection a `Connection` address
    /// names, which needs no watch: through the registry, as the services'
    /// sends are made; `Error(Nil)` when no connection is there, and the request
    /// is dropped. Made once at start; a rule never sees it.
    deliver: fn(step.Address, request) -> Result(Nil, Nil),
  )
}

/// The listener's reference, which `ranch:handshake` takes the socket by.
pub type RanchRef

/// A client socket, owned by its connection's process.
type ClientSocket

/// Why the socket could not be taken from Ranch: the client was gone before the
/// handshake finished, or the socket's options could not be set.
type HandshakeFailure {
  ClientGone(failure: SocketFailure)
  SocketOptionsFailed(failure: SocketFailure)
}

/// What the socket sent the process, decoded from its Erlang message by
/// `genesis_prime_connection_shell_ffi:socket_message`.
type SocketMessage {
  Read(bytes: BitArray)
  ClosedByPeer
  FailedToRead(failure: SocketFailure)
}

/// Everything that reaches the actor, each as a typed value by its selector
/// (`selector`). A message no other selector takes is `Stray`.
type Mail(message, answer) {
  /// The first message: the actor sends it to itself as it starts, so the
  /// handshake runs after `start` has returned to Ranch.
  Begin
  FromSocket(message: SocketMessage)
  /// The exit of the parent, Ranch's connection supervisor: the server is
  /// stopping.
  ParentExited
  /// The exit of any other linked process, which the shell ignores.
  OtherExited
  /// Another process sent the connection a message (`registry.deliver`).
  Delivered(message: message)
  /// A timer fired: its message names the timer's id and the reference of the
  /// start it came from (`script.Elapsed`).
  TimerElapsed(timer: TimerId, reference: Reference)
  /// A monitored process ended: a watch's target or a kept ask's.
  Ended(down: process.Down)
  /// An ask's answer, tagged with the ask's reference, whether the shell
  /// still waits for it or not.
  AnswerArrived(tag: Reference, answer: answer)
  /// A message no other selector takes.
  Stray(message: Dynamic)
}

/// A timer the shell started through its script's scheduler: how to cancel it,
/// and the reference its message carries, which tells its timeout from a stale
/// one of an earlier timer of the same id.
type Started {
  Started(cancel: Cancel, reference: Reference)
}

/// How an ask's wait ended.
type Waited(answer) {
  Replied(answer: answer)
  TargetEnded
  ParentStopping
  DeadlinePassed
}

/// An ask whose outcome came without an answer: its tag and its monitor are
/// kept until the target answers or ends.
type Kept {
  Kept(monitor: Monitor)
}

/// A connection that has taken its socket: the socket, its script, the rule's
/// state, the recording files when there are any, the `Now` of the input whose
/// step is being carried out and the node's own monotonic time for it (the two
/// an ask's wait counts its deadline from), whether it is
/// taking what the socket delivers or putting one recorded read together, the
/// asks kept by their tags, the monitor of each watch the rule has open, each
/// timer it has running and the stop deadline of a stop that arrived during an
/// ask.
type Running(state, request) {
  Running(
    socket: ClientSocket,
    script: Script,
    state: state,
    wire: Option(WireWriter),
    at: step.Now,
    taken_ms: Int,
    reading: Reading,
    kept: Dict(Reference, Kept),
    /// The watches the rule has open, which keep the way to tell each process
    /// a watch found until the watch ends or is dropped.
    watches: Watches(fn(request) -> Nil),
    timers: Dict(TimerId, Started),
    stopping: Option(Int),
    /// The side the recording's closing line names: the client once the shell
    /// has taken the socket's close, the server until then. The rule may ask
    /// before it stops, so the step that stops is not always the one that took
    /// the close, and the side is kept from that input.
    closed_by: Side,
  )
}

/// How the connection takes what its socket delivers.
type Reading {
  /// The bytes that arrive are the next `Read` input. A server's connection is
  /// always here, since its script fixes no size for a read.
  TakeWhatArrives
  /// The script gave the byte count `wanted` of the next recorded read, which
  /// is more than has arrived: the connection holds `held` and takes no input
  /// until the rest has come, and then takes the one `Read`. `deadline_ms` is
  /// the time on the node's monotonic clock by which the rest must have come,
  /// counted once from the first part, so parts that keep arriving do not put it
  /// off.
  Reassembling(held: BitArray, wanted: Int, deadline_ms: Int)
}

/// Where the connection is: waiting to take its socket from Ranch, or open.
type Status(state, request) {
  /// Started by Ranch and holding its reference; `Begin` takes the socket.
  AwaitingHandshake(ranch_ref: RanchRef)
  Open(running: Running(state, request))
}

/// The actor's state: what it is started with and keeps for its life (the
/// settings, the parent, the subject its timers fire on, the subject its asks
/// are answered on) and its status.
type Connection(settings, state, message, answer, request) {
  Connection(
    settings: Settings(settings, state, message, answer, request),
    parent: Pid,
    timers: Subject(Elapsed),
    answers: Subject(#(Reference, answer)),
    status: Status(state, request),
  )
}

/// How long `start` waits for the actor's initialiser, which returns at once.
const start_timeout_ms = 5000

/// Starts the connection's actor, linked to the calling process, which is
/// Ranch's connection supervisor and the shell's parent. Called only by
/// `genesis_prime_connection_shell_ffi:start_link`, and returns at once: the handshake runs
/// in the actor's first message, since Ranch sends it only after `start_link`
/// has returned.
pub fn start(
  ranch_ref ranch_ref: RanchRef,
  settings settings: Settings(settings, state, message, answer, request),
) -> Result(Pid, actor.StartError) {
  let parent = process.self()
  actor.new_with_initialiser(start_timeout_ms, fn(subject) {
    Ok(initialise(subject:, ranch_ref:, settings:, parent:))
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.pid })
}

/// Keeps the actor's waiting messages off its heap, queues `Begin` for itself
/// and returns, so Ranch's connection supervisor is never kept waiting. Exits
/// are not trapped yet: a parent that stops before the handshake ends the
/// actor, which holds no socket and no recording.
fn initialise(
  subject subject: Subject(Mail(message, answer)),
  ranch_ref ranch_ref: RanchRef,
  settings settings: Settings(settings, state, message, answer, request),
  parent parent: Pid,
) -> actor.Initialised(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
  Nil,
) {
  let _previous = process_flag(MessageQueueData, OffHeap)
  let answers = process.new_subject()
  let timers = process.new_subject()
  process.send(subject, Begin)
  actor.initialised(Connection(
    settings:,
    parent:,
    timers:,
    answers:,
    status: AwaitingHandshake(ranch_ref:),
  ))
  |> actor.selecting(selector(
    subject:,
    timers:,
    answers:,
    parent:,
    registry: settings.registry,
  ))
  |> actor.returning(Nil)
}

/// Every message a connection takes, as `Mail`: its own subject (`Begin`), the
/// subject its timers fire on, the ask answers, what the socket sends, the exits of the
/// parent and of other processes, the messages other processes deliver, the
/// end of every monitored process and, last, any other message as `Stray`.
fn selector(
  subject subject: Subject(Mail(message, answer)),
  timers timers: Subject(Elapsed),
  answers answers: Subject(#(Reference, answer)),
  parent parent: Pid,
  registry registry: Option(Registry(message)),
) -> Selector(Mail(message, answer)) {
  process.new_selector()
  |> process.select_other(Stray)
  |> process.select(subject)
  |> process.select_map(timers, fn(elapsed) {
    TimerElapsed(timer: elapsed.timer, reference: elapsed.reference)
  })
  |> process.select_map(answers, fn(reply) {
    AnswerArrived(tag: reply.0, answer: reply.1)
  })
  |> process.merge_selector(socket_and_exits(parent))
  |> select_delivered(registry)
  |> process.select_monitors(Ended)
}

/// The messages other processes deliver through the registry; a connection
/// with no registry is found by no process and takes none.
fn select_delivered(
  selector: Selector(Mail(message, answer)),
  registry: Option(Registry(message)),
) -> Selector(Mail(message, answer)) {
  case registry {
    Some(registry) -> registry.select_delivered(registry, selector, Delivered)
    None -> selector
  }
}

/// The first elements of the socket's messages, as the atoms `tcp`,
/// `tcp_closed` and `tcp_error`.
type SocketTag {
  Tcp
  TcpClosed
  TcpError
}

fn from_socket(sent: Dynamic) -> Mail(message, answer) {
  FromSocket(socket_message(sent))
}

/// Takes one message by the connection's status. `Begin` takes the socket
/// (`begin`); once open, a read, the peer's close, a read failure, the
/// parent's exit, a delivered message, a timer's firing or a watch's end is
/// the rule's next input (`take`), and the end or the answer of a kept ask,
/// a stale timer and another process's exit are dropped. A stray message is
/// dropped and logged by its kind.
fn handle(
  connection: Connection(settings, state, message, answer, request),
  mail: Mail(message, answer),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case connection.status {
    AwaitingHandshake(ranch_ref:) ->
      case mail {
        Begin -> begin(connection:, ranch_ref:)
        FromSocket(..)
        | ParentExited
        | OtherExited
        | Delivered(..)
        | TimerElapsed(..)
        | Ended(..)
        | AnswerArrived(..)
        | Stray(..) ->
          panic as "a connection takes Begin first: its initialiser queued it before Ranch could send anything"
      }
    Open(running:) ->
      case mail {
        Begin -> panic as "a connection takes Begin once"
        FromSocket(Read(bytes:)) -> read_arrived(connection:, running:, bytes:)
        FromSocket(ClosedByPeer) ->
          take_next(connection:, running:, event: OwnEvent(step.PeerClosed))
        FromSocket(FailedToRead(failure:)) ->
          take_next(
            connection:,
            running:,
            event: OwnEvent(step.ReadFailed(failure:)),
          )
        ParentExited -> {
          let now = running.script.clock(wire_recording.Stopping)
          take(
            connection:,
            running:,
            now:,
            event: Stopping(deadline_ms: stop_deadline(now, connection.settings)),
          )
        }
        OtherExited -> keep_open(connection:, running:)
        Delivered(message:) ->
          take_next(
            connection:,
            running:,
            event: OwnEvent(step.Woken(message:)),
          )
        TimerElapsed(timer:, reference:) ->
          timer_elapsed(connection:, running:, timer:, reference:)
        Ended(down:) -> ended(connection:, running:, down:)
        AnswerArrived(tag:, ..) -> late_answer(connection:, running:, tag:)
        Stray(message:) -> {
          runtime.log_stray(message:, shell: "connection shell")
          keep_open(connection:, running:)
        }
      }
  }
}

/// Takes the socket from Ranch, traps exits so the parent's stop arrives as a
/// message, sets the logger metadata of the process (connection and peer),
/// opens the recording, joins the registry and takes `Accepted` as the rule's
/// first input. A handshake that fails (a client gone, or a socket whose
/// options cannot be set) ends the connection quietly with `actor.stop`, with
/// a debug line, nothing to close and nothing recorded.
fn begin(
  connection connection: Connection(settings, state, message, answer, request),
  ranch_ref ranch_ref: RanchRef,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let settings = connection.settings
  case handshake(ranch_ref, settings.send_deadline_ms, frame.read_limit) {
    Error(failure) -> {
      runtime.log(LogDebug, describe_handshake(failure), step.no_one)
      actor.stop()
    }
    Ok(socket) ->
      case settings.scripts() {
        Ok(issued) -> accepted(connection:, socket:, issued:)
        Error(Nil) -> {
          runtime.log(
            LogWarning,
            "no script for the connection, so it is closed",
            step.no_one,
          )
          close(socket)
          actor.stop()
        }
      }
  }
}

/// Takes `Accepted` as the rule's first input, with the seed of the script the
/// settings handed the connection and the `Now` its clock gives (the clock's
/// first call): traps exits so the parent's stop arrives as a message, sets the
/// logger metadata of the process (connection and peer), opens the recordings
/// and joins the registry.
fn accepted(
  connection connection: Connection(settings, state, message, answer, request),
  socket socket: ClientSocket,
  issued issued: Issued,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let settings = connection.settings
  let script = issued.script
  process.trap_exits(True)
  let id = runtime.unique_id()
  let accepted = peer(socket)
  runtime.set_about(
    step.About(
      ..step.no_one,
      connection: Some(ConnectionId(id)),
      peer: Some(accepted),
    ),
  )
  let wire = case
    recorder.open_if(
      recorder: settings.wire_recorder,
      rule_name: settings.rule.name,
      connection: id,
      accept_ordinal: issued.ordinal,
      seed: script.seed,
    )
  {
    Ok(wire) -> wire
    Error(error) -> wire_recording_failed(socket, error)
  }
  join_registry(settings.registry, ConnectionId(id))
  let rule = settings.rule
  let now = script.clock(wire_recording.Accepted)
  take(
    connection:,
    running: Running(
      socket:,
      script:,
      state: rule.new(rule.settings),
      wire:,
      at: now,
      taken_ms: script.node_monotonic_ms(now),
      reading: TakeWhatArrives,
      kept: dict.new(),
      watches: watch.new(),
      timers: dict.new(),
      stopping: None,
      closed_by: wire_recording.Server,
    ),
    now:,
    event: OwnEvent(Accepted(
      connection: ConnectionId(id),
      peer: accepted,
      seed: seed.bytes(script.seed),
    )),
  )
}

/// A sentence that says why the connection could not take its socket.
fn describe_handshake(failure: HandshakeFailure) -> String {
  case failure {
    ClientGone(failure:) ->
      "the client left before the handshake finished: "
      <> step.describe_socket_failure(failure)
    SocketOptionsFailed(failure:) ->
      "the socket options could not be set: "
      <> step.describe_socket_failure(failure)
  }
}

/// Joins the connection's group in the registry, when the settings hold one.
fn join_registry(
  registry: Option(Registry(message)),
  connection: ConnectionId,
) -> Nil {
  case registry {
    Some(registry) -> registry.join(registry:, connection:)
    None -> Nil
  }
}

/// Takes an input with the time the script's clock gives it, which is that
/// clock's one call for the input.
fn take_next(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  event event: Event(ConnectionEvent(message, answer)),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  take(
    connection:,
    running:,
    now: running.script.clock(wire_input(event)),
    event:,
  )
}

/// The one way an input reaches the rule: the wire recorder writes its line,
/// the rule takes it, and the step's effects are carried out. `now` is
/// the one call of the script's clock that was made for this input (`take_next`
/// makes it; the three inputs whose `Now` an earlier decision needs make it
/// themselves), so the clock is called once for each input taken and for
/// nothing the shell drops.
fn take(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  now now: step.Now,
  event event: Event(ConnectionEvent(message, answer)),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case
    recorder.taken(
      writer: running.wire,
      sequence: wire_sequence(running.wire),
      at: now,
      input: wire_input(event),
    )
  {
    Ok(Nil) -> Nil
    Error(error) -> wire_recording_failed(running.socket, error)
  }
  let rule = connection.settings.rule
  let #(state, step) = rule.step(running.state, Input(now:, event:))
  let closing = case event {
    OwnEvent(step.PeerClosed) -> wire_recording.Client
    OwnEvent(Accepted(..))
    | OwnEvent(step.Read(..))
    | OwnEvent(Answered(..))
    | OwnEvent(step.TimerFired(..))
    | OwnEvent(ReadFailed(..))
    | OwnEvent(WriteFailed(..))
    | OwnEvent(step.Woken(..))
    | step.WatchEnded(..)
    | Stopping(..) -> running.closed_by
  }
  let running =
    Running(
      ..running,
      state:,
      at: now,
      taken_ms: running.script.node_monotonic_ms(now),
      closed_by: closing,
    )
  case step {
    Effects(effects:) ->
      carry(connection:, running:, effects:, then: WaitForInput, closing:)
    EffectsThenAsk(effects:, ask:) ->
      carry(connection:, running:, effects:, then: MakeAsk(ask), closing:)
  }
}

/// Takes what the socket delivered as a `Read` input. The server's script fixes
/// no size (`script.NextRead`), so the bytes that arrived are the input. A
/// replay's script gives the byte count of the next recorded read; when fewer
/// bytes have arrived the connection is `Reassembling`: it holds them and arms
/// the socket again, taking no input, until it holds that many, so a read the
/// socket delivers in parts reaches the rule as the one recorded input, and no
/// other input (an answer, for one) is taken between the parts. Bytes held
/// beyond the count are part of the same input. A close or a failure of the
/// socket takes the held bytes with it.
fn read_arrived(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  bytes bytes: BitArray,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let #(held, wanted) = case running.reading {
    Reassembling(held:, wanted:, ..) -> #(
      <<held:bits, bytes:bits>>,
      Some(wanted),
    )
    TakeWhatArrives -> #(bytes, running.script.next_read())
  }
  let held_count = bit_array.byte_size(held)
  case wanted {
    Some(wanted) if held_count < wanted ->
      case read_once(running.socket) {
        Ok(Nil) -> {
          let deadline_ms = case running.reading {
            Reassembling(deadline_ms:, ..) -> deadline_ms
            TakeWhatArrives -> runtime.monotonic_ms() + held_read_wait_ms
          }
          wait_for_rest(
            connection:,
            running: Running(
              ..running,
              reading: Reassembling(held:, wanted:, deadline_ms:),
            ),
            deadline_ms:,
          )
        }
        Error(failure) ->
          take_next(
            connection:,
            running: Running(..running, reading: TakeWhatArrives),
            event: OwnEvent(ReadFailed(failure:)),
          )
      }
    Some(_) | None ->
      take_next(
        connection:,
        running: Running(..running, reading: TakeWhatArrives),
        event: OwnEvent(step.Read(bytes: held)),
      )
  }
}

/// How long the shell waits, in real milliseconds, for the rest of a read it
/// holds part of: the bound that ends the wait when the rest never comes.
const held_read_wait_ms = 5000

/// Waits for the rest of a read the shell holds part of, with a selective
/// receive that takes only the socket's messages and the exits (the parent's is
/// the server's stop, another process's is dropped), until `deadline_ms`, an
/// absolute time on the monotonic clock fixed by the first part. Everything
/// else, a delivered message, a timer, a watch's end, a late answer, stays in
/// the mailbox, so the read is taken before any of it and the rule gets the
/// inputs in the order the recording holds. A message the wait takes is handled
/// as the actor would handle it. When the bound passes, the shell stops waiting
/// and the actor takes the next message of the mailbox, the bytes still held.
fn wait_for_rest(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  deadline_ms deadline_ms: Int,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case
    receive_until(
      selector: socket_and_exits(connection.parent),
      deadline_ms:,
      skip: fn(mail) {
        case mail {
          OtherExited -> True
          Begin
          | FromSocket(..)
          | ParentExited
          | Delivered(..)
          | TimerElapsed(..)
          | Ended(..)
          | AnswerArrived(..)
          | Stray(..) -> False
        }
      },
    )
  {
    Ok(mail) -> handle(Connection(..connection, status: Open(running:)), mail)
    Error(Nil) -> keep_open(connection:, running:)
  }
}

/// Receives the next message the selector takes that `skip` does not say to
/// pass over, until `deadline_ms`, an absolute time on the node's monotonic
/// clock that is read again after each message passed over, so no stream of
/// messages puts the deadline off. `Error(Nil)` when the deadline passes first,
/// also when it has already passed.
fn receive_until(
  selector selector: Selector(heard),
  deadline_ms deadline_ms: Int,
  skip skip: fn(heard) -> Bool,
) -> Result(heard, Nil) {
  let remaining = deadline_ms - runtime.monotonic_ms()
  case remaining <= 0 {
    True -> Error(Nil)
    False ->
      case process.selector_receive(selector, within: remaining) {
        Ok(heard) ->
          case skip(heard) {
            True -> receive_until(selector:, deadline_ms:, skip:)
            False -> Ok(heard)
          }
        Error(Nil) -> Error(Nil)
      }
  }
}

/// The socket's messages and the exits, as `Mail`: what the shell takes while it
/// waits for the rest of a read.
fn socket_and_exits(parent: Pid) -> Selector(Mail(message, answer)) {
  process.new_selector()
  |> process.select_record(tag: Tcp, fields: 2, mapping: from_socket)
  |> process.select_record(tag: TcpClosed, fields: 1, mapping: from_socket)
  |> process.select_record(tag: TcpError, fields: 2, mapping: from_socket)
  |> process.select_trapped_exits(fn(exit) {
    case exit.pid == parent {
      True -> ParentExited
      False -> OtherExited
    }
  })
}

/// The sequence number of a wire recording's next line, taken as the line's
/// event happens; 0 when nothing is recorded.
fn wire_sequence(wire: Option(WireWriter)) -> Int {
  case wire {
    Some(_) -> runtime.unique_id()
    None -> 0
  }
}

/// The kind of an input as the wire recording keeps it.
fn wire_input(
  event: Event(ConnectionEvent(message, answer)),
) -> wire_recording.Input {
  case event {
    OwnEvent(Accepted(..)) -> wire_recording.Accepted
    OwnEvent(step.Read(bytes:)) -> wire_recording.Read(bytes:)
    OwnEvent(Answered(outcome:, ..)) ->
      wire_recording.Answered(outcome: wire_outcome(outcome))
    OwnEvent(step.TimerFired(timer: step.TimerId(number))) ->
      wire_recording.TimerFired(timer: number)
    OwnEvent(step.PeerClosed) -> wire_recording.PeerClosed
    OwnEvent(ReadFailed(..)) -> wire_recording.ReadFailed
    OwnEvent(WriteFailed(..)) -> wire_recording.WriteFailed
    OwnEvent(step.Woken(..)) -> wire_recording.Woken
    step.WatchEnded(..) -> wire_recording.WatchEnded
    Stopping(..) -> wire_recording.Stopping
  }
}

/// How an ask ended, without its answer.
fn wire_outcome(outcome: step.Outcome(answer)) -> wire_recording.Outcome {
  case outcome {
    Answer(..) -> wire_recording.Answer
    NotRunning -> wire_recording.NotRunning
    EndedBeforeAnswer -> wire_recording.EndedBeforeAnswer
    NoAnswerInTime -> wire_recording.NoAnswerInTime
    StoppedWaiting -> wire_recording.StoppedWaiting
  }
}

/// What the shell does once a step's effects are carried out.
type Then(request) {
  /// Take the next input.
  WaitForInput
  /// Make this ask and wait for its outcome.
  MakeAsk(ask: Ask(request))
  /// End the process, the connection ended by `by`: the step held a `Stop`,
  /// which drops its ask.
  EndProcess(by: Side)
}

/// Carries out the effects in order, then does what `then` says. A `Stop`
/// among the effects does not end the step: the effects after it are carried
/// out, then the process ends, and a failed write after it ends the process
/// with no `WriteFailed` input.
fn carry(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  effects effects: List(Effect(ConnectionEffect(request))),
  then then: Then(request),
  closing closing: Side,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case effects {
    [] -> finish(connection:, running:, then:)
    [effect, ..later] ->
      carry_effect(connection:, running:, effect:, later:, then:, closing:)
  }
}

/// Carries out one effect, then the later ones with `carry`: a write (a
/// failed one is the next input, `WriteFailed`, or, after a `Stop`, ends the
/// connection with a warning), a log line, a `Stop`, a watch or unwatch, a
/// timer started through the script's scheduler on the connection's timer
/// subject, or cancelled.
fn carry_effect(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  effect effect: Effect(ConnectionEffect(request)),
  later later: List(Effect(ConnectionEffect(request))),
  then then: Then(request),
  closing closing: Side,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case effect {
    OwnEffect(Write(bytes:)) -> {
      let sequence = wire_sequence(running.wire)
      case send(running.socket, bytes), then {
        Ok(Nil), _ ->
          case recorder.sent(writer: running.wire, sequence:, bytes:) {
            Ok(Nil) ->
              carry(connection:, running:, effects: later, then:, closing:)
            Error(error) -> wire_recording_failed(running.socket, error)
          }
        Error(failure), EndProcess(..) -> {
          runtime.log(
            LogWarning,
            "a write after the rule's Stop failed ("
              <> step.describe_socket_failure(failure)
              <> "), so the connection ends",
            step.no_one,
          )
          stop(running:, by: wire_recording.Server)
        }
        Error(failure), MakeAsk(..) | Error(failure), WaitForInput ->
          take_next(
            connection:,
            running:,
            event: OwnEvent(WriteFailed(failure:)),
          )
      }
    }
    step.Log(line:) -> {
      runtime.log(line.level, line.text, line.about)
      carry(connection:, running:, effects: later, then:, closing:)
    }
    step.Stop ->
      carry(
        connection:,
        running:,
        effects: later,
        then: EndProcess(by: closing),
        closing:,
      )
    step.Watch(watch:, target:) ->
      carry(
        connection:,
        running: open_watch(connection:, running:, watch:, target:),
        effects: later,
        then:,
        closing:,
      )
    step.Unwatch(watch:) ->
      carry(
        connection:,
        running: Running(
          ..running,
          watches: watch.close(watches: running.watches, watch:),
        ),
        effects: later,
        then:,
        closing:,
      )
    OwnEffect(StartTimer(timer:, after_ms:)) ->
      carry(
        connection:,
        running: start_timer(connection:, running:, timer:, after_ms:),
        effects: later,
        then:,
        closing:,
      )
    OwnEffect(step.Tell(to:, request:)) -> {
      tell(connection:, running:, to:, request:)
      carry(connection:, running:, effects: later, then:, closing:)
    }
    OwnEffect(CancelTimer(timer:)) ->
      carry(
        connection:,
        running: cancel_timer(running:, timer:),
        effects: later,
        then:,
        closing:,
      )
    OwnEffect(step.TellWatched(watch:, request:)) -> {
      case watch.sender_of(watches: running.watches, watch:) {
        Ok(sender) -> sender(request)
        Error(Nil) -> Nil
      }
      carry(connection:, running:, effects: later, then:, closing:)
    }
    OwnEffect(step.JoinGroup(address:)) -> {
      join_group(connection:, address:)
      carry(connection:, running:, effects: later, then:, closing:)
    }
    OwnEffect(step.LeaveGroup(address:)) -> {
      leave_group(connection:, address:)
      carry(connection:, running:, effects: later, then:, closing:)
    }
  }
}

/// Makes the connection's process a member of the registry's group at
/// `address` (`registry.join_group`); a connection with no registry in its
/// settings has no group to join, which is a bug of the rule that asked.
fn join_group(
  connection connection: Connection(settings, state, message, answer, request),
  address address: step.Address,
) -> Nil {
  case connection.settings.registry {
    Some(registry) -> registry.join_group(registry:, address:)
    None -> panic as "a rule joined a group on a connection with no registry"
  }
}

/// Removes the connection's process from the registry's group at `address`
/// (`registry.leave_group`).
fn leave_group(
  connection connection: Connection(settings, state, message, answer, request),
  address address: step.Address,
) -> Nil {
  case connection.settings.registry {
    Some(registry) -> registry.leave_group(registry:, address:)
    None -> panic as "a rule left a group on a connection with no registry"
  }
}

/// Monitors the process the address names under the watch's id, with the way
/// to tell it when the lookup found one.
fn open_watch(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  watch watch: step.WatchId,
  target target: step.Address,
) -> Running(state, request) {
  Running(
    ..running,
    watches: watch.open(
      watches: running.watches,
      watch:,
      address: target,
      target: connection.settings.locate(target),
      shell: "connection shell",
    ),
  )
}

/// Tells the process at the address the request. A connection is sent it
/// through the settings' `deliver`, which finds it in the registry; one that
/// has ended drops it, as a send to a gone process is dropped, with no line
/// since a player's viewers end all the time. Any other process is told through
/// the way the open watch on that address found, so a move costs no lookup, and
/// a tell to an address no open watch found a process for is dropped with a
/// warning: the watch was dropped, the process ended, or it was never running.
fn tell(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  to to: step.Address,
  request request: request,
) -> Nil {
  case to {
    step.Connection(..) | step.ZoneChannel(..) -> {
      let _delivered = connection.settings.deliver(to, request)
      Nil
    }
    step.Sessions
    | step.HandOff
    | step.Store
    | step.Maps
    | step.Map(..)
    | step.CharacterNamed(..) ->
      case watch.sender_at(watches: running.watches, address: to) {
        Ok(sender) -> sender(request)
        Error(Nil) ->
          runtime.log(
            LogWarning,
            "a tell was dropped: no open watch holds a process at its address",
            step.no_one,
          )
      }
  }
}

/// Starts the timer the rule named, with a reference of its own that its
/// timeout carries; an id already running ends the connection.
fn start_timer(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  timer timer: TimerId,
  after_ms after_ms: Int,
) -> Running(state, request) {
  case dict.has_key(running.timers, timer) {
    True -> {
      runtime.log(
        LogError,
        "a rule started a timer whose id is already running, which the connection shell does not carry out",
        step.no_one,
      )
      close(running.socket)
      panic as "a rule started a timer whose id is already running"
    }
    False -> {
      let reference = reference.new()
      let cancel =
        running.script.schedule(connection.timers, timer, reference, after_ms)
      Running(
        ..running,
        timers: dict.insert(running.timers, timer, Started(cancel:, reference:)),
      )
    }
  }
}

/// Cancels the timer the rule named and forgets it. A timeout already sent is
/// discarded when it arrives, since no timer holds its reference.
fn cancel_timer(
  running running: Running(state, request),
  timer timer: TimerId,
) -> Running(state, request) {
  case dict.get(running.timers, timer) {
    Ok(Started(cancel:, ..)) -> {
      cancel()
      Running(..running, timers: dict.delete(running.timers, timer))
    }
    Error(Nil) -> running
  }
}

/// What the shell does after a step's effects. A step that ends in an ask
/// when a stop arrived during an earlier ask gets `Answered(_, StoppedWaiting)`
/// at once, with no call to the directory.
fn finish(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  then then: Then(request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case then, running.stopping {
    EndProcess(by:), _ -> stop(running:, by:)
    MakeAsk(ask:), None -> make_ask(connection:, running:, ask:)
    MakeAsk(ask:), Some(_) ->
      take_next(
        connection:,
        running:,
        event: OwnEvent(Answered(ask: ask.ask, outcome: StoppedWaiting)),
      )
    WaitForInput, _ -> wait_for_input(connection:, running:)
  }
}

/// Before the next message is taken: the end of each watch of a target no
/// process holds, in the order opened, as `WatchEnded`; then a stop that
/// arrived during an ask, as `Stopping`; otherwise the socket's next read is
/// asked for and the actor takes its next message.
fn wait_for_input(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case watch.next_unheld_end(running.watches), running.stopping {
    Ok(#(watch, watches)), _ ->
      take_next(
        connection:,
        running: Running(..running, watches:),
        event: step.WatchEnded(watch:),
      )
    Error(Nil), Some(deadline_ms) ->
      take_next(
        connection:,
        running: Running(..running, stopping: None),
        event: Stopping(deadline_ms:),
      )
    Error(Nil), None ->
      case read_once(running.socket) {
        Ok(Nil) -> keep_open(connection:, running:)
        Error(failure) ->
          take_next(
            connection:,
            running:,
            event: OwnEvent(ReadFailed(failure:)),
          )
      }
  }
}

/// Makes an ask through the settings' directory, whose reply sends the answer
/// to the connection's answers subject tagged with the ask's reference, and
/// waits for its outcome.
fn make_ask(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  ask ask: Ask(request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let tag = reference.new()
  let answers = connection.answers
  let reply = fn(answer) { process.send(answers, #(tag, answer)) }
  let deadline_ms = real_deadline_ms(running:, ask:)
  case connection.settings.directory(ask.request, deadline_ms, reply) {
    Error(Nil) ->
      take_next(
        connection:,
        running:,
        event: OwnEvent(Answered(ask: ask.ask, outcome: NotRunning)),
      )
    Ok(service.NoReplyInTime) ->
      take_next(
        connection:,
        running:,
        event: OwnEvent(Answered(ask: ask.ask, outcome: NoAnswerInTime)),
      )
    Ok(service.ToService(pid:) as sent) | Ok(service.ToWorker(pid:) as sent) ->
      wait_for_answer(
        connection:,
        running:,
        ask:,
        tag:,
        sent:,
        pid:,
        deadline_ms:,
      )
  }
}

/// The ask's deadline on the node's own monotonic clock, which every wait of
/// the shell and the directory's lookups count on: the time the ask allows from
/// the `Now` of the input whose step made it (the ask's deadline less that
/// input's monotonic time), counted from the node's time for the input
/// (`taken_ms`). In the server the two clocks are one reading and this is the
/// ask's own deadline; in a replay the input's `Now` comes from the recording,
/// whose monotonic times are of another run, so only the time allowed carries
/// over.
fn real_deadline_ms(
  running running: Running(state, request),
  ask ask: Ask(request),
) -> Int {
  running.taken_ms + ask.deadline_ms - running.at.monotonic_ms
}

/// Watches the process the ask went to and waits for the ask's outcome, until
/// `deadline_ms` on the node's own clock. An ask that ends without an answer, by
/// its deadline or the server's stop, is kept by its tag until the target
/// answers or ends.
fn wait_for_answer(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  ask ask: Ask(request),
  tag tag: Reference,
  sent sent: Sent,
  pid pid: Pid,
  deadline_ms deadline_ms: Int,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let monitor = process.monitor(pid)
  let #(waited, kept) =
    await_answer(
      answers: connection.answers,
      tag:,
      monitor:,
      parent: connection.parent,
      kept: running.kept,
      deadline_ms:,
    )
  let outcome = case waited {
    Replied(answer:) -> Answer(answer:)
    TargetEnded -> EndedBeforeAnswer
    DeadlinePassed -> NoAnswerInTime
    ParentStopping -> StoppedWaiting
  }
  let known =
    running.script.clock(
      wire_recording.Answered(outcome: wire_outcome(outcome)),
    )
  let running = Running(..running, kept:)
  let running = case waited {
    Replied(..) | TargetEnded -> running
    DeadlinePassed -> {
      service.end_worker(sent)
      keep(running:, tag:, monitor:)
    }
    ParentStopping ->
      Running(
        ..keep(running:, tag:, monitor:),
        stopping: Some(stop_deadline(known, connection.settings)),
      )
  }
  take(
    connection:,
    running:,
    now: known,
    event: OwnEvent(Answered(ask: ask.ask, outcome:)),
  )
}

/// What an ask's wait heard.
type Heard(answer) {
  AnswerHeard(tag: Reference, answer: answer)
  TargetDown
  ParentGone
  OtherGone
}

/// Waits for the outcome of the ask tagged `tag` by a selective receive that
/// takes only the answers subject, the target's monitor and the exits (the
/// parent's ends the wait, another process's is dropped), until the deadline,
/// an absolute time on the monotonic clock; a deadline already passed ends the
/// wait at once. Every other message stays in the mailbox, so the rule's next
/// inputs come in the order they arrived. An answer to the ask drops its
/// monitor, with the DOWN that may already wait (`process.demonitor_process`
/// flushes it), so no monitor stays on the target. The answer of a kept ask (an
/// earlier ask's, past its deadline) is taken from the subject here too, since
/// a subject cannot be received by tag: its monitor is dropped and the kept ask
/// with it, and the kept asks that remain come back with the outcome. The
/// answer of no kept ask is dropped.
fn await_answer(
  answers answers: Subject(#(Reference, answer)),
  tag tag: Reference,
  monitor monitor: Monitor,
  parent parent: Pid,
  kept kept: Dict(Reference, Kept),
  deadline_ms deadline_ms: Int,
) -> #(Waited(answer), Dict(Reference, Kept)) {
  let selector =
    process.new_selector()
    |> process.select_map(answers, fn(reply) {
      AnswerHeard(tag: reply.0, answer: reply.1)
    })
    |> process.select_specific_monitor(monitor, fn(_down) { TargetDown })
    |> process.select_trapped_exits(fn(exit) {
      case exit.pid == parent {
        True -> ParentGone
        False -> OtherGone
      }
    })
  wait_until(selector:, tag:, monitor:, kept:, deadline_ms:)
}

/// Receives until the deadline on the node's own monotonic clock (`receive_until`),
/// so no stream of other messages puts the deadline off and the wait ends within
/// the time the ask allowed.
fn wait_until(
  selector selector: Selector(Heard(answer)),
  tag tag: Reference,
  monitor monitor: Monitor,
  kept kept: Dict(Reference, Kept),
  deadline_ms deadline_ms: Int,
) -> #(Waited(answer), Dict(Reference, Kept)) {
  case
    receive_until(selector:, deadline_ms:, skip: fn(heard) {
      case heard {
        OtherGone -> True
        AnswerHeard(..) | TargetDown | ParentGone -> False
      }
    })
  {
    Ok(AnswerHeard(tag: heard, answer:)) if heard == tag -> {
      process.demonitor_process(monitor)
      #(Replied(answer:), kept)
    }
    Ok(AnswerHeard(tag: heard, ..)) ->
      wait_until(
        selector:,
        tag:,
        monitor:,
        kept: drop_kept(kept:, tag: heard),
        deadline_ms:,
      )
    Ok(TargetDown) -> #(TargetEnded, kept)
    Ok(ParentGone) -> #(ParentStopping, kept)
    Ok(OtherGone) -> wait_until(selector:, tag:, monitor:, kept:, deadline_ms:)
    Error(Nil) -> #(DeadlinePassed, kept)
  }
}

/// Keeps an ask's tag and monitor until its target answers or ends.
fn keep(
  running running: Running(state, request),
  tag tag: Reference,
  monitor monitor: Monitor,
) -> Running(state, request) {
  Running(..running, kept: dict.insert(running.kept, tag, Kept(monitor:)))
}

/// The one end of a connection that was open: closes the socket, ends the
/// recording (the closing line, which names `by`, the side that ended it: the
/// client when the step that stopped took the socket's close, the server
/// otherwise) and lets the actor stop normally. Every stop of an open
/// connection goes through it: the rule's `Stop`, also after a write that
/// failed. A crash does not: the process ends with its reason, the socket
/// closes with it, and the recording has no closing line, so it never replays.
fn stop(
  running running: Running(state, request),
  by by: Side,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  close(running.socket)
  runtime.finish_wire_recording(writer: running.wire, by:)
  actor.stop()
}

/// Ends the connection before its input is taken or the next effect carried
/// out, since the socket's read or write could not be recorded.
fn wire_recording_failed(socket: ClientSocket, error: WriteError) -> a {
  runtime.log_wire_recording_failure(error)
  close(socket)
  panic as "a connection's wire recording could not be written"
}

/// Continues with the connection open.
fn keep_open(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  actor.continue(Connection(..connection, status: Open(running:)))
}

/// Takes a timer's firing as `TimerFired` when its reference is the current
/// start's of that id, and forgets the timer; a stale one is dropped.
fn timer_elapsed(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  timer timer: TimerId,
  reference reference: Reference,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case dict.get(running.timers, timer) {
    Ok(Started(reference: current, ..)) if current == reference ->
      take_next(
        connection:,
        running: Running(..running, timers: dict.delete(running.timers, timer)),
        event: OwnEvent(step.TimerFired(timer:)),
      )
    Ok(Started(..)) | Error(Nil) -> keep_open(connection:, running:)
  }
}

/// Takes the end of a monitored process: a kept ask's target only drops the
/// ask's tag, a watch's target is the rule's `WatchEnded`, and the DOWN of a
/// monitor the shell holds under neither is dropped.
fn ended(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  down down: process.Down,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let monitor = runtime.down_monitor(down)
  case kept_with_monitor(running.kept, monitor) {
    Ok(tag) ->
      keep_open(
        connection:,
        running: Running(..running, kept: dict.delete(running.kept, tag)),
      )
    Error(Nil) ->
      case watch.ended(watches: running.watches, monitor:) {
        Ok(#(watch, watches)) ->
          take_next(
            connection:,
            running: Running(..running, watches:),
            event: step.WatchEnded(watch:),
          )
        Error(Nil) -> keep_open(connection:, running:)
      }
  }
}

/// The tag of the kept ask whose target `monitor` watches.
fn kept_with_monitor(
  kept: Dict(Reference, Kept),
  monitor: Monitor,
) -> Result(Reference, Nil) {
  dict.to_list(kept)
  |> list.find(fn(entry) { { entry.1 }.monitor == monitor })
  |> result.map(fn(entry) { entry.0 })
}

/// Drops the answer of a kept ask, which gives the rule no input, with the
/// ask's monitor; the answer of no kept ask is dropped as it is.
fn late_answer(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state, request),
  tag tag: Reference,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  keep_open(
    connection:,
    running: Running(..running, kept: drop_kept(kept: running.kept, tag:)),
  )
}

/// Forgets the kept ask tagged `tag`, if there is one, and drops its monitor.
fn drop_kept(
  kept kept: Dict(Reference, Kept),
  tag tag: Reference,
) -> Dict(Reference, Kept) {
  case dict.get(kept, tag) {
    Ok(Kept(monitor:)) -> {
      process.demonitor_process(monitor)
      dict.delete(kept, tag)
    }
    Error(Nil) -> kept
  }
}

/// The deadline a stopping rule is given: the shutdown time from when the
/// shell takes the exit, less the send deadline, which covers a write the shell
/// was in when the exit arrived (a write waits at most the send deadline before
/// its socket closes). An exit that waited behind a longer step is counted from
/// when it is taken, so Ranch, which counts from when it sent the stop, may
/// kill the process first.
fn stop_deadline(
  now: step.Now,
  settings: Settings(settings, state, message, answer, request),
) -> Int {
  now.monotonic_ms + settings.shutdown_ms - settings.send_deadline_ms
}

/// What `erlang:process_flag` sets: where a process keeps its waiting
/// messages.
type ProcessFlag {
  MessageQueueData
}

/// Where a process keeps its waiting messages: outside its heap, which the
/// garbage collector then does not scan each time a message waits.
type QueueLocation {
  OffHeap
}

/// The flag's value before it was set, which the shell does not read.
type PreviousQueueLocation

/// Sets the flag and gives its old value.
@external(erlang, "erlang", "process_flag")
fn process_flag(
  flag: ProcessFlag,
  location: QueueLocation,
) -> PreviousQueueLocation

@external(erlang, "genesis_prime_connection_shell_ffi", "handshake")
fn handshake(
  ranch_ref: RanchRef,
  send_deadline_ms: Int,
  read_limit: Int,
) -> Result(ClientSocket, HandshakeFailure)

@external(erlang, "genesis_prime_connection_shell_ffi", "peer")
fn peer(socket: ClientSocket) -> step.Peer

@external(erlang, "genesis_prime_connection_shell_ffi", "read_once")
fn read_once(socket: ClientSocket) -> Result(Nil, SocketFailure)

@external(erlang, "genesis_prime_connection_shell_ffi", "send")
fn send(socket: ClientSocket, bytes: BitArray) -> Result(Nil, SocketFailure)

@external(erlang, "genesis_prime_connection_shell_ffi", "socket_message")
fn socket_message(sent: Dynamic) -> SocketMessage

@external(erlang, "genesis_prime_connection_shell_ffi", "close")
fn close(socket: ClientSocket) -> Nil
