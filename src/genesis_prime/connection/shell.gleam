//// The shell of a connection: the process that owns one client socket and
//// runs one rule over it, a gleam_otp actor that Ranch starts. It turns everything that reaches the process into
//// the rule's inputs, carries out the rule's effects in order and decides
//// nothing, so a recording of its inputs replays every decision with no socket
//// (genesis_prime/rule_recording).
////
//// One connection, from accept to end:
////
//// ```
//// Ranch accepts ─▶ connection_shell_ffi:start_link ─▶ start: the actor
////   initialiser: waiting messages off the heap, exits trapped, Begin sent to
////     itself, returns at once; Ranch then sends the handshake
////   Begin ─▶ ranch:handshake, the socket's options, the logger metadata of
////     the process (connection, peer)
////   the recorder, when on, opens the file and writes the header
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
////   each step: the recorder writes Taken(input, step) before its effects
//// ```
////
//// - **A handshake that fails.** A client gone before the handshake, or a
////   socket that cannot be set up, ends the connection normally with a debug
////   line and no warning or error: no recording was opened and no step ran.
//// - **A message the selector does not take.** gleam_otp drops it and logs a
////   warning, which carries the connection's metadata.
//// - **Time.** Each input carries one `Now`, read as the shell takes the
////   input: the monotonic clock in milliseconds and the system time as a
////   FILETIME.
//// - **A failed write.** The step's later effects are not carried out; the
////   next input is `OwnEvent(WriteFailed(_))`. A write that does not finish
////   within the send deadline fails as `SendTimedOut` and closes the socket.
//// - **Stop.** The shell carries out the rest of the step's effects in order,
////   closes the socket, the recorder writes `End` with the count of inputs,
////   and the process ends normally; a step with a `Stop` makes no ask, and a
////   failed write after the `Stop` is logged as a warning, closes the socket
////   and ends the process with no `WriteFailed` input. Bytes still queued
////   get the send deadline, in whole seconds, to go out before the close drops
////   them. A rule must return
////   `Stop` after `PeerClosed` or `ReadFailed`, since no other socket input
////   reaches the process then.
//// - **The server stopping.** The shell traps its parent's exit, so the
////   tree's stop arrives as `Stopping`, with a deadline of the listener's
////   shutdown time less the send deadline, never later than Ranch's kill. A
////   rule that has not stopped by then is killed, and its recording has no
////   `End`.
//// - **A crash.** When the rule's step crashes, the actor ends with that
////   reason; Ranch starts connection processes as temporary children, so
////   nothing restarts it and the listener goes on accepting. The socket closes
////   with the process, and its recording has no `End`, so it never replays.
//// - **A recording that cannot be written.** The shell logs it, closes the
////   socket and ends the process before that step's effects, so no input is
////   carried out without its record; the recording has no `End`.
//// - **An ask.** A step that ends in `EffectsThenAsk` has its effects carried
////   out first; a failed write or a `Stop` among them means the ask is never
////   made. The shell then hands the request and a reply, tagged with a fresh
////   reference, to the settings' `directory`, and waits, taking no other
////   input, until the outcome:
////
//// ```
//// directory(request, the ask's deadline, reply)
////   Error(Nil)              ─▶ Answered(ask, NotRunning), nothing sent
////   Ok(ToService(pid))      ─▶ monitor pid, wait until the ask's deadline
////   Ok(ToWorker(pid))       ─▶ monitor pid, wait until the ask's deadline
//// waiting:
////   {ask answer, tag, a}    ─▶ Answered(ask, Answer(a))
////   the target's DOWN       ─▶ Answered(ask, EndedBeforeAnswer)
////   the deadline passes     ─▶ Answered(ask, NoAnswerInTime); a worker is
////                                ended (exit shutdown) first
////   the parent's exit       ─▶ Answered(ask, StoppedWaiting) at once, then
////                                Stopping(arrival + shutdown_ms
////                                         - send_deadline_ms)
//// after NoAnswerInTime or StoppedWaiting, the tag and the monitor are kept
////   until the target's answer or DOWN; between steps:
////   {ask answer, tag, _} of a kept tag ─▶ tag dropped, no input
////   the DOWN of a kept tag             ─▶ tag dropped, no input
////   an answer or DOWN of no kept tag   ─▶ dropped
//// ```
////
////   The wait is a selective receive inside the handler, and the answers
////   arrive on one subject the connection keeps, each tagged with its ask's
////   reference. While it waits, a system message (`sys:get_state`) waits too,
////   up to the ask's deadline.
////
////   A step that follows `StoppedWaiting` and ends in another ask gets
////   `Answered(_, StoppedWaiting)` at once, with no call to the directory, so
////   every ask has one `Answered`; `Stopping` is the next input after a step
////   that ends without an ask. A worker answers late only when its answer left
////   before the shell's exit reached it. A late answer gives the rule no input,
////   whether it comes after `NoAnswerInTime` or after `StoppedWaiting`. The
////   `Now` of `Answered` is read when the outcome is known.
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
//// - **A message delivered.** Another process sends the connection's pid
////   `{woken, message}` (`registry.deliver`); the shell takes it between steps
////   as `OwnEvent(Woken(message))`, in the order it arrived among the socket's
////   reads. One that arrives during an ask waits until the ask's outcome and
////   the step it starts are done, like a read. A message for a connection that has ended is
////   dropped by the VM, and one that arrives after the shell began to stop is
////   dropped with the process. A connection with no registry in its settings is
////   joined to no group, so no process can send it anything.
//// - **A watch.** `Watch(id, target)` finds the target's pid with the settings'
////   `locate`, monitors it and keeps the monitor under `id`
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
//// - **A timer.** `StartTimer(id, ms)` starts a `process.send_after` that sends
////   the shell's own subject `TimerElapsed(id, reference)`, kept under `id`
////   with its own reference. It is taken between steps as
////   `OwnEvent(TimerFired(id))`, once, and the shell forgets the timer; one
////   that fires during an ask waits like a delivered message. `CancelTimer(id)`
////   cancels it and forgets it, so no `TimerFired` follows: a message that
////   had fired or is in flight when it is cancelled is discarded on arrival,
////   as is any message whose reference is not the current timer's of that id,
////   so a cancelled timer's message never fires a restarted timer of the same
////   id. An id with no
////   running timer is cancelled to nothing. An id already running ends the
////   connection with an error log.
//// - **The registry's scope ending.** The connection stays joined only as long
////   as the scope lives; the tree restarts the game listener with the scope, so
////   no connection outlives it (genesis_prime/connection/registry).
//// - **Effects and inputs of the other kind.** A connection's own effects are
////   `Write`, `StartTimer` and `CancelTimer`, and its own inputs are the
////   socket's, `Woken`, `TimerFired` and `Answered` (`ConnectionEffect` and
////   `ConnectionEvent`). It has no `Reply`, `Send` or `Started`, so a rule that
////   answers a caller, sends, or takes a service's input does not compile
////   against this shell.

import genesis_prime/connection/registry.{type Registry}
import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/service.{type Locate, type Sent}
import genesis_prime/step.{
  type Ask, type ConnectionEffect, type ConnectionEvent, type ConnectionId,
  type ConnectionRule, type Effect, type Event, type SocketFailure, type TimerId,
  Accepted, Answer, Answered, ConnectionId, Effects, EffectsThenAsk,
  EndedBeforeAnswer, LogDebug, NoAnswerInTime, NotRunning, OwnEvent,
  StoppedWaiting, Stopping,
}
import genesis_prime/step/runtime
import genesis_prime/step/watch.{type Watches}
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{
  type Monitor, type Pid, type Selector, type Subject, type Timer,
}
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
    /// Where each connection's inputs are recorded; `None` unless the dev
    /// start turns recording on.
    recorder: Option(Recorder),
    /// How the shell reaches the process a request names: it sends the
    /// request with `reply` and says where it went, or `Error(Nil)` when that
    /// process is not running. Made once at start from the services' names,
    /// with `service.call` and `store/worker.ask`; a rule never sees it.
    directory: fn(request, Int, fn(answer) -> Nil) -> Result(Sent, Nil),
    /// Where each connection joins as it is accepted, so other processes
    /// find it by its id; `None` for a connection no process addresses (the
    /// login's).
    registry: Option(Registry),
    /// How the shell finds the process a `Watch` names. Made once at start
    /// from the processes' names; a rule never sees it.
    locate: Locate,
  )
}

/// The listener's reference, which `ranch:handshake` takes the socket by.
pub type RanchRef

/// A client socket, owned by its connection's process.
type ClientSocket

/// What the socket sent the process, decoded from its Erlang message by
/// `connection_shell_ffi:socket_message`.
type SocketMessage {
  Read(bytes: BitArray)
  ClosedByPeer
  FailedToRead(failure: SocketFailure)
}

/// Everything that reaches the actor, each as a typed value by its selector
/// (`selector`). A message the selector does not take is dropped and logged
/// by gleam_otp.
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
  /// start it came from.
  TimerElapsed(timer: TimerId, reference: Reference)
  /// A monitored process ended: a watch's target or a kept ask's.
  Ended(down: process.Down)
  /// An ask's answer, tagged with the ask's reference, whether the shell
  /// still waits for it or not.
  AnswerArrived(tag: Reference, answer: answer)
}

/// A timer the shell started and the reference its message carries, which
/// tells its timeout from a stale one of an earlier timer of the same id.
type Started {
  Started(timer: Timer, reference: Reference)
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

/// A connection that has taken its socket: the socket, the rule's state, the
/// recording file when there is one, the asks kept by their tags, the monitor
/// of each watch the rule has open, each timer it has running and the stop
/// deadline of a stop that arrived during an ask.
type Running(state) {
  Running(
    socket: ClientSocket,
    state: state,
    writer: Option(file.Writer),
    kept: Dict(Reference, Kept),
    watches: Watches,
    timers: Dict(TimerId, Started),
    stopping: Option(Int),
  )
}

/// Where the connection is: waiting to take its socket from Ranch, or open.
type Status(state) {
  /// Started by Ranch and holding its reference; `Begin` takes the socket.
  AwaitingHandshake(ranch_ref: RanchRef)
  Open(running: Running(state))
}

/// The actor's state: what it is started with and keeps for its life (the
/// settings, the parent, its own subject for the timers it starts, the subject
/// its asks are answered on) and its status.
type Connection(settings, state, message, answer, request) {
  Connection(
    settings: Settings(settings, state, message, answer, request),
    parent: Pid,
    subject: Subject(Mail(message, answer)),
    answers: Subject(#(Reference, answer)),
    status: Status(state),
  )
}

/// How long `start` waits for the actor's initialiser, which returns at once.
const start_timeout_ms = 5000

/// Starts the connection's actor, linked to the calling process, which is
/// Ranch's connection supervisor and the shell's parent. Called only by
/// `connection_shell_ffi:start_link`, and returns at once: the handshake runs
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

/// Keeps the actor's waiting messages off its heap, traps exits so the
/// parent's stop arrives as a message, queues `Begin` for itself and returns,
/// so Ranch's connection supervisor is never kept waiting.
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
  process.trap_exits(True)
  let answers = process.new_subject()
  process.send(subject, Begin)
  actor.initialised(Connection(
    settings:,
    parent:,
    subject:,
    answers:,
    status: AwaitingHandshake(ranch_ref:),
  ))
  |> actor.selecting(selector(subject:, answers:, parent:))
  |> actor.returning(Nil)
}

/// Every message a connection takes, as `Mail`: its own subject (`Begin` and
/// the timers), the ask answers, what the socket sends, the exits of the
/// parent and of other processes, the messages other processes deliver, and
/// the end of every monitored process.
fn selector(
  subject subject: Subject(Mail(message, answer)),
  answers answers: Subject(#(Reference, answer)),
  parent parent: Pid,
) -> Selector(Mail(message, answer)) {
  process.new_selector()
  |> process.select(subject)
  |> process.select_map(answers, fn(reply) {
    AnswerArrived(tag: reply.0, answer: reply.1)
  })
  |> process.select_record(tag: Tcp, fields: 2, mapping: from_socket)
  |> process.select_record(tag: TcpClosed, fields: 1, mapping: from_socket)
  |> process.select_record(tag: TcpError, fields: 2, mapping: from_socket)
  |> process.select_trapped_exits(fn(exit) {
    case exit.pid == parent {
      True -> ParentExited
      False -> OtherExited
    }
  })
  |> registry.select_delivered(Delivered)
  |> process.select_monitors(Ended)
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
/// a stale timer and another process's exit are dropped.
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
        | AnswerArrived(..) ->
          panic as "a connection takes Begin first: its initialiser queued it before Ranch could send anything"
      }
    Open(running:) -> {
      let now = runtime.now()
      case mail {
        Begin -> panic as "a connection takes Begin once"
        FromSocket(Read(bytes:)) ->
          take(connection:, running:, now:, event: OwnEvent(step.Read(bytes:)))
        FromSocket(ClosedByPeer) ->
          take(connection:, running:, now:, event: OwnEvent(step.PeerClosed))
        FromSocket(FailedToRead(failure:)) ->
          take(
            connection:,
            running:,
            now:,
            event: OwnEvent(step.ReadFailed(failure:)),
          )
        ParentExited ->
          take(
            connection:,
            running:,
            now:,
            event: Stopping(deadline_ms: stop_deadline(now, connection.settings)),
          )
        OtherExited -> keep_open(connection:, running:)
        Delivered(message:) ->
          take(
            connection:,
            running:,
            now:,
            event: OwnEvent(step.Woken(message:)),
          )
        TimerElapsed(timer:, reference:) ->
          timer_elapsed(connection:, running:, now:, timer:, reference:)
        Ended(down:) -> ended(connection:, running:, now:, down:)
        AnswerArrived(tag:, ..) -> late_answer(connection:, running:, tag:)
      }
    }
  }
}

/// Takes the socket from Ranch, sets the logger metadata of the process
/// (connection and peer), opens the recording, joins the registry and takes
/// `Accepted` as the rule's first input. A client gone before the handshake
/// ends the connection quietly with `actor.stop`, with nothing to close or to
/// record.
fn begin(
  connection connection: Connection(settings, state, message, answer, request),
  ranch_ref ranch_ref: RanchRef,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let settings = connection.settings
  case handshake(ranch_ref, settings.send_deadline_ms) {
    Error(failure) -> {
      runtime.log(
        LogDebug,
        "the client left before the handshake finished: "
          <> step.describe_socket_failure(failure),
        step.no_one,
      )
      actor.stop()
    }
    Ok(socket) -> {
      let id = runtime.unique_id()
      let accepted = peer(socket)
      runtime.set_about(
        step.About(
          ..step.no_one,
          connection: Some(ConnectionId(id)),
          peer: Some(accepted),
        ),
      )
      let writer = case
        file.open_if(settings.recorder, settings.rule, connection: id)
      {
        Ok(writer) -> writer
        Error(error) -> recording_failed(socket, error)
      }
      join_registry(settings.registry, ConnectionId(id))
      let rule = settings.rule
      take(
        connection:,
        running: Running(
          socket:,
          state: rule.new(rule.settings),
          writer:,
          kept: dict.new(),
          watches: watch.new(),
          timers: dict.new(),
          stopping: None,
        ),
        now: runtime.now(),
        event: OwnEvent(Accepted(
          connection: ConnectionId(id),
          peer: accepted,
          seed: crypto.strong_random_bytes(32),
        )),
      )
    }
  }
}

/// Joins the connection's group in the registry, when the settings hold one.
fn join_registry(registry: Option(Registry), connection: ConnectionId) -> Nil {
  case registry {
    Some(registry) -> registry.join(registry:, connection:)
    None -> Nil
  }
}

/// Folds one input through the rule, records it, then carries out the step.
fn take(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state),
  now now: step.Now,
  event event: Event(ConnectionEvent(message, answer)),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let #(state, step, writer) = case
    file.fold(
      rule: connection.settings.rule,
      state: running.state,
      writer: running.writer,
      now:,
      event:,
    )
  {
    Ok(taken) -> taken
    Error(error) -> recording_failed(running.socket, error)
  }
  let running = Running(..running, state:, writer:)
  case step {
    Effects(effects:) ->
      carry(connection:, running:, effects:, then: WaitForInput)
    EffectsThenAsk(effects:, ask:) ->
      carry(connection:, running:, effects:, then: MakeAsk(ask))
  }
}

/// What the shell does once a step's effects are carried out.
type Then(request) {
  /// Take the next input.
  WaitForInput
  /// Make this ask and wait for its outcome.
  MakeAsk(ask: Ask(request))
  /// End the process: the step held a `Stop`, which drops its ask.
  EndProcess
}

/// Carries out the effects in order, then does what `then` says. A `Stop`
/// among the effects does not end the step: the effects after it are carried
/// out, then the process ends, and a failed write after it ends the process
/// with no `WriteFailed` input.
fn carry(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state),
  effects effects: List(Effect(ConnectionEffect)),
  then then: Then(request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case effects {
    [] -> finish(connection:, running:, then:)
    [effect, ..later] ->
      carry_effect(connection:, running:, effect:, later:, then:)
  }
}

/// Carries out one effect, then the later ones with `carry`: a write (a
/// failed one is the next input, `WriteFailed`), a log line, a `Stop`, a
/// watch or unwatch, a timer started with `process.send_after` on the
/// connection's own subject, or cancelled with `process.cancel_timer`.
fn carry_effect(
  connection _connection: Connection(settings, state, message, answer, request),
  running _running: Running(state),
  effect _effect: Effect(ConnectionEffect),
  later _later: List(Effect(ConnectionEffect)),
  then _then: Then(request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  panic as "built in the next commit"
}

/// What the shell does after a step's effects. A step that ends in an ask
/// when a stop arrived during an earlier ask gets `Answered(_, StoppedWaiting)`
/// at once, with no call to the directory.
fn finish(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state),
  then then: Then(request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case then, running.stopping {
    EndProcess, _ -> stop(running)
    MakeAsk(ask:), None -> make_ask(connection:, running:, ask:)
    MakeAsk(ask:), Some(_) ->
      take(
        connection:,
        running:,
        now: runtime.now(),
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
  connection _connection: Connection(settings, state, message, answer, request),
  running _running: Running(state),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  panic as "built in the next commit"
}

/// Makes an ask through the settings' directory, whose reply sends the answer
/// to the connection's answers subject tagged with the ask's reference, and
/// waits for its outcome.
fn make_ask(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state),
  ask ask: Ask(request),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let tag = reference.new()
  let answers = connection.answers
  let reply = fn(answer) { process.send(answers, #(tag, answer)) }
  case connection.settings.directory(ask.request, ask.deadline_ms, reply) {
    Error(Nil) ->
      take(
        connection:,
        running:,
        now: runtime.now(),
        event: OwnEvent(Answered(ask: ask.ask, outcome: NotRunning)),
      )
    Ok(sent) -> wait_for_answer(connection:, running:, ask:, tag:, sent:)
  }
}

/// Watches the process the ask went to and waits for the ask's outcome. An
/// ask that ends without an answer, by its deadline or the server's stop, is
/// kept by its tag until the target answers or ends.
fn wait_for_answer(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state),
  ask ask: Ask(request),
  tag tag: Reference,
  sent sent: Sent,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let monitor = process.monitor(sent.pid)
  let #(waited, kept) =
    await_answer(
      answers: connection.answers,
      tag:,
      monitor:,
      parent: connection.parent,
      kept: running.kept,
      deadline_ms: ask.deadline_ms,
    )
  let known = runtime.now()
  let running = Running(..running, kept:)
  let #(running, outcome) = case waited {
    Replied(answer:) -> #(running, Answer(answer:))
    TargetEnded -> #(running, EndedBeforeAnswer)
    DeadlinePassed -> {
      service.end_worker(sent)
      #(keep(running:, tag:, monitor:), NoAnswerInTime)
    }
    ParentStopping -> #(
      Running(
        ..keep(running:, tag:, monitor:),
        stopping: Some(stop_deadline(known, connection.settings)),
      ),
      StoppedWaiting,
    )
  }
  take(
    connection:,
    running:,
    now: known,
    event: OwnEvent(Answered(ask: ask.ask, outcome:)),
  )
}

/// Waits for the outcome of the ask tagged `tag` by a selective receive that
/// takes only that tag's answer on the answers subject, the target's monitor
/// and the exits (the parent's ends the wait, another process's is dropped),
/// until the deadline, an absolute time on the monotonic clock; a deadline
/// already passed ends the wait at once. Every other message stays in the
/// mailbox, so the rule's next inputs come in the order they arrived. The
/// answer of a kept ask (an earlier ask's, past its deadline) is taken from
/// the subject here too, since a subject cannot be received by tag: its
/// monitor is dropped and the kept ask with it, and the kept asks that remain
/// come back with the outcome. The answer of no kept ask is dropped.
fn await_answer(
  answers _answers: Subject(#(Reference, answer)),
  tag _tag: Reference,
  monitor _monitor: Monitor,
  parent _parent: Pid,
  kept _kept: Dict(Reference, Kept),
  deadline_ms _deadline_ms: Int,
) -> #(Waited(answer), Dict(Reference, Kept)) {
  panic as "built in the next commit"
}

/// Keeps an ask's tag and monitor until its target answers or ends.
fn keep(
  running running: Running(state),
  tag tag: Reference,
  monitor monitor: Monitor,
) -> Running(state) {
  Running(..running, kept: dict.insert(running.kept, tag, Kept(monitor:)))
}

/// The one end of a connection that was open: closes the socket, ends the
/// recording with `End` and lets the actor stop normally. Every stop of an
/// open connection goes through it: the rule's `Stop`, also after a write
/// that failed. A crash does not: the process ends with its reason, the socket
/// closes with it, and the recording has no `End`, so it never replays.
fn stop(
  running: Running(state),
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  close(running.socket)
  runtime.finish_recording(running.writer)
  actor.stop()
}

/// Ends the connection before the step's effects, since its input could not
/// be recorded.
fn recording_failed(socket: ClientSocket, error: FileError) -> a {
  runtime.log_recording_failure(error)
  close(socket)
  panic as "a connection's recording could not be written"
}

/// Continues with the connection open.
fn keep_open(
  connection connection: Connection(settings, state, message, answer, request),
  running running: Running(state),
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
  running running: Running(state),
  now now: step.Now,
  timer timer: TimerId,
  reference reference: Reference,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case dict.get(running.timers, timer) {
    Ok(Started(reference: current, ..)) if current == reference ->
      take(
        connection:,
        running: Running(..running, timers: dict.delete(running.timers, timer)),
        now:,
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
  running running: Running(state),
  now now: step.Now,
  down down: process.Down,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  let monitor = case down {
    process.ProcessDown(monitor:, ..) | process.PortDown(monitor:, ..) ->
      monitor
  }
  case kept_with_monitor(running.kept, monitor) {
    Ok(tag) ->
      keep_open(
        connection:,
        running: Running(..running, kept: dict.delete(running.kept, tag)),
      )
    Error(Nil) ->
      case watch.ended(watches: running.watches, monitor:) {
        Ok(#(watch, watches)) ->
          take(
            connection:,
            running: Running(..running, watches:),
            now:,
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
  running running: Running(state),
  tag tag: Reference,
) -> actor.Next(
  Connection(settings, state, message, answer, request),
  Mail(message, answer),
) {
  case dict.get(running.kept, tag) {
    Ok(Kept(monitor:)) -> {
      process.demonitor_process(monitor)
      keep_open(
        connection:,
        running: Running(..running, kept: dict.delete(running.kept, tag)),
      )
    }
    Error(Nil) -> keep_open(connection:, running:)
  }
}

/// The deadline a stopping rule is given: the shutdown time from now, less
/// the send deadline, since Ranch's timer started when it sent the stop and
/// the shell may then have been in a write, which waits at most the send
/// deadline before its socket closes. So the deadline is never later than
/// the moment Ranch kills the process.
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

@external(erlang, "connection_shell_ffi", "handshake")
fn handshake(
  ranch_ref: RanchRef,
  send_deadline_ms: Int,
) -> Result(ClientSocket, SocketFailure)

@external(erlang, "connection_shell_ffi", "peer")
fn peer(socket: ClientSocket) -> step.Peer

@external(erlang, "connection_shell_ffi", "socket_message")
fn socket_message(sent: Dynamic) -> SocketMessage

@external(erlang, "connection_shell_ffi", "close")
fn close(socket: ClientSocket) -> Nil
