//// The shell of a connection: the process that owns one client socket and
//// runs one rule over it. It turns everything that reaches the process into
//// the rule's inputs, carries out the rule's effects in order and decides
//// nothing, so a recording of its inputs replays every decision with no socket
//// (genesis_prime/rule_recording).
////
//// One connection, from accept to end:
////
//// ```
//// Ranch accepts ─▶ connection_shell_ffi:start_link ─▶ ranch:handshake ─▶ run
////   the recorder, when on, opens the file and writes the header
////   Socket(Accepted(connection id, peer))        ─▶ step ─▶ effects
////   loop, the socket active once:
////     {tcp, bytes}        ─▶ Socket(Read(bytes))   ─▶ step ─▶ effects
////     {tcp_closed}        ─▶ Socket(PeerClosed)    ─▶ step ─▶ effects
////     {tcp_error, reason} ─▶ Socket(ReadFailed(_)) ─▶ step ─▶ effects
////     the parent's exit   ─▶ Stopping(now + shutdown_ms) ─▶ step ─▶ effects
////   each step: the recorder writes Taken(input, step) before its effects
//// ```
////
//// - **Time.** Each input carries one `Now`, read as the shell takes the
////   input: the monotonic clock in milliseconds and the system time as a
////   FILETIME.
//// - **A failed write.** The step's later effects are not carried out; the
////   next input is `Socket(WriteFailed(_))`. A write that does not finish
////   within the send deadline fails as `SendTimedOut` and closes the socket.
//// - **Stop.** The shell closes the socket, the recorder writes `End` with
////   the count of inputs, and the process ends normally. Bytes still queued
////   get the send deadline, in whole seconds, to go out before the close drops
////   them. A rule must return
////   `Stop` after `PeerClosed` or `ReadFailed`, since no other socket input
////   reaches the process then.
//// - **The server stopping.** The shell traps its parent's exit, so the
////   tree's stop arrives as `Stopping`, with a deadline of the listener's
////   shutdown time less the send deadline, never later than Ranch's kill. A rule that has not stopped by then is killed, and
////   its recording has no `End`.
//// - **A crash.** When the rule's step crashes, the process ends with that
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
//// directory(request, reply)
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
////   {ask answer, tag, _} of a kept tag ─▶ AnsweredLate(ask), tag dropped
////   the DOWN of a kept tag             ─▶ tag dropped, no input
////   an answer or DOWN of no kept tag   ─▶ dropped
//// ```
////
////   A step that follows `StoppedWaiting` and ends in another ask does not
////   make it: `Stopping` is the next input. A worker answers late only when
////   its answer left before the shell's exit reached it. The `Now` of `Answered` is read when the outcome is known.
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
//// - **Effects a connection does not carry out.** `Reply` (a connection is
////   never asked), and `Send`, `Watch`, `Unwatch`, `StartTimer` and
////   `CancelTimer`, which need processes no rule uses yet: the shell logs an
////   error naming the effect and ends the connection.

import genesis_prime/rule_recording.{Taken}
import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/service/shell.{type Sent, ToService, ToWorker}
import genesis_prime/step.{
  type About, type Ask, type AskId, type Effect, type Event, type LogLevel,
  type Peer, type Rule, type SocketFailure, About, Accepted, Answer, Answered,
  AnsweredLate, ConnectionId, Effects, EffectsThenAsk, EndedBeforeAnswer, Input,
  LogError, NoAnswerInTime, NotRunning, Now, PeerClosed, ReadFailed, Socket,
  StoppedWaiting, Stopping, WriteFailed,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference.{type Reference}
import gleam/option.{type Option, None, Some}

/// What every connection of one listener is started with.
pub type Settings(settings, state, message, answer, outgoing, request) {
  Settings(
    rule: Rule(settings, state, message, answer, outgoing, request),
    /// How long a write may wait for the socket before it fails as
    /// `SendTimedOut`.
    send_deadline_ms: Int,
    /// How long a connection has to stop once the server stops.
    shutdown_ms: Int,
    /// Where each connection's inputs are recorded; `None` unless the dev
    /// start turns recording on.
    recorder: Option(Recorder(settings)),
    /// How the shell reaches the process a request names: it sends the
    /// request with `reply` and says where it went, or `Error(Nil)` when that
    /// process is not running. Made once at start from the services' names,
    /// with `service/shell.call` and `store/worker.ask`; a rule never sees it.
    directory: fn(request, fn(answer) -> Nil) -> Result(Sent, Nil),
  )
}

/// A client socket, owned by its connection's process.
type ClientSocket

/// What reaches the process between steps, as `connection_shell_ffi` sees it.
type Arrived {
  Read(bytes: BitArray)
  ClosedByPeer
  FailedToRead(failure: SocketFailure)
  StopRequested
  /// The answer of a kept ask, by its tag.
  LateAnswer(tag: Reference)
  /// The end of a kept ask's target, by the ask's tag.
  KeptEnded(tag: Reference)
}

/// How an ask's wait ended, as `connection_shell_ffi` sees it.
type Waited(answer) {
  Replied(answer: answer)
  TargetEnded
  ParentExited
  DeadlinePassed
}

/// An ask whose outcome came without an answer: its tag and its monitor are
/// kept until the target answers or ends.
type Kept {
  Kept(ask: AskId, monitor: Reference)
}

/// Why a process is asked to exit; the atom `shutdown`.
type ExitReason {
  Shutdown
}

/// A running connection: its socket, its parent, its settings, the rule's
/// state, the recording file when there is one, the asks kept by their tags
/// and the stop deadline of a stop that arrived during an ask.
type Running(settings, state, message, answer, outgoing, request) {
  Running(
    socket: ClientSocket,
    parent: Pid,
    settings: Settings(settings, state, message, answer, outgoing, request),
    state: state,
    writer: Option(file.Writer),
    kept: Dict(Reference, Kept),
    stopping: Option(Int),
  )
}

/// Runs one connection to its end, in the process Ranch started for it.
/// `ranch_ref` is the listener's reference for `ranch:handshake` and `parent`
/// Ranch's connection supervisor. Called only by
/// `connection_shell_ffi:start_link`.
pub fn run(
  ranch_ref ranch_ref: Dynamic,
  parent parent: Pid,
  settings settings: Settings(
    settings,
    state,
    message,
    answer,
    outgoing,
    request,
  ),
) -> Nil {
  let socket = handshake(ranch_ref, settings.send_deadline_ms)
  let connection = unique_id()
  let writer = case settings.recorder {
    None -> None
    Some(recorder) ->
      case file.open(recorder, connection:) {
        Ok(writer) -> Some(writer)
        Error(error) -> recording_failed(socket, error)
      }
  }
  let rule = settings.rule
  let running =
    Running(
      socket:,
      parent:,
      settings:,
      state: rule.new(rule.settings),
      writer:,
      kept: dict.new(),
      stopping: None,
    )
  take(
    running:,
    now: now(),
    event: Socket(Accepted(ConnectionId(connection), peer(socket))),
  )
}

/// Folds one input through the rule, records it, then carries out the step.
fn take(
  running running: Running(settings, state, message, answer, outgoing, request),
  now now: step.Now,
  event event: Event(message, answer),
) -> Nil {
  let input = Input(now:, event:)
  let #(state, step) = running.settings.rule.step(running.state, input)
  let writer = case running.writer {
    None -> None
    Some(writer) ->
      case file.append(writer, Taken(input:, step:)) {
        Ok(writer) -> Some(writer)
        Error(error) -> recording_failed(running.socket, error)
      }
  }
  let running = Running(..running, state:, writer:)
  case step {
    Effects(effects:) -> carry(running:, effects:, ask: None)
    EffectsThenAsk(effects:, ask:) -> carry(running:, effects:, ask: Some(ask))
  }
}

/// Carries out the effects in order, then makes the ask if there is one, or
/// waits for the next input. A stop that arrived during an ask is the next
/// input before either.
fn carry(
  running running: Running(settings, state, message, answer, outgoing, request),
  effects effects: List(Effect(outgoing)),
  ask ask: Option(Ask(request)),
) -> Nil {
  case effects {
    [] ->
      case running.stopping, ask {
        Some(deadline_ms), _ ->
          take(
            running: Running(..running, stopping: None),
            now: now(),
            event: Stopping(deadline_ms:),
          )
        None, None -> wait(running)
        None, Some(ask) -> make_ask(running, ask)
      }
    [effect, ..later] ->
      case effect {
        step.Write(bytes:) ->
          case send(running.socket, bytes) {
            Ok(Nil) -> carry(running:, effects: later, ask:)
            Error(failure) ->
              take(running:, now: now(), event: Socket(WriteFailed(failure:)))
          }
        step.Log(line:) -> {
          log(line.level, line.text, line.about)
          carry(running:, effects: later, ask:)
        }
        step.Stop -> stop(running)
        step.Send(..) -> not_built(running.socket, "Send")
        step.Reply(..) -> not_built(running.socket, "Reply")
        step.Watch(..) -> not_built(running.socket, "Watch")
        step.Unwatch(..) -> not_built(running.socket, "Unwatch")
        step.StartTimer(..) -> not_built(running.socket, "StartTimer")
        step.CancelTimer(..) -> not_built(running.socket, "CancelTimer")
      }
  }
}

/// Waits for what reaches the process next and takes it as an input.
fn wait(
  running: Running(settings, state, message, answer, outgoing, request),
) -> Nil {
  case read_once(running.socket) {
    Error(failure) ->
      take(running:, now: now(), event: Socket(ReadFailed(failure:)))
    Ok(Nil) -> next(running)
  }
}

/// Takes what reaches the process next as an input. The end of a kept ask's
/// target is no input; it only drops the tag.
fn next(
  running: Running(settings, state, message, answer, outgoing, request),
) -> Nil {
  let arrived = next_event(running.socket, running.parent, running.kept)
  let now = now()
  case arrived {
    Read(bytes:) -> take(running:, now:, event: Socket(step.Read(bytes:)))
    ClosedByPeer -> take(running:, now:, event: Socket(PeerClosed))
    FailedToRead(failure:) ->
      take(running:, now:, event: Socket(ReadFailed(failure:)))
    StopRequested ->
      take(
        running:,
        now:,
        event: Stopping(deadline_ms: stop_deadline(now, running.settings)),
      )
    LateAnswer(tag:) -> {
      let assert Ok(Kept(ask:, monitor:)) = dict.get(running.kept, tag)
        as "an answer is taken as late only for a tag the shell kept"
      unwatch(monitor)
      take(
        running: Running(..running, kept: dict.delete(running.kept, tag)),
        now:,
        event: AnsweredLate(ask:),
      )
    }
    KeptEnded(tag:) ->
      next(Running(..running, kept: dict.delete(running.kept, tag)))
  }
}

/// Makes an ask through the settings' directory and waits for its outcome,
/// taking no other input.
fn make_ask(
  running: Running(settings, state, message, answer, outgoing, request),
  ask: Ask(request),
) -> Nil {
  let tag = reference.new()
  let shell = process.self()
  let reply = fn(answer) { send_answer(shell, tag, answer) }
  case running.settings.directory(ask.request, reply) {
    Error(Nil) ->
      take(
        running:,
        now: now(),
        event: Answered(ask: ask.ask, outcome: NotRunning),
      )
    Ok(sent) -> wait_for_answer(running:, ask:, tag:, sent:)
  }
}

/// Watches the process the ask went to and waits for the ask's outcome. An
/// ask that ends without an answer, by its deadline or the server's stop, is
/// kept by its tag until the target answers or ends.
fn wait_for_answer(
  running running: Running(settings, state, message, answer, outgoing, request),
  ask ask: Ask(request),
  tag tag: Reference,
  sent sent: Sent,
) -> Nil {
  let monitor = watch(target(sent))
  let waited = await_answer(tag, monitor, running.parent, ask.deadline_ms)
  let known = now()
  let #(running, outcome) = case waited {
    Replied(answer:) -> #(running, Answer(answer:))
    TargetEnded -> #(running, EndedBeforeAnswer)
    DeadlinePassed -> {
      end_worker(sent)
      #(keep(running:, tag:, ask: ask.ask, monitor:), NoAnswerInTime)
    }
    ParentExited -> #(
      Running(
        ..keep(running:, tag:, ask: ask.ask, monitor:),
        stopping: Some(stop_deadline(known, running.settings)),
      ),
      StoppedWaiting,
    )
  }
  take(running:, now: known, event: Answered(ask: ask.ask, outcome:))
}

/// The process an ask went to.
fn target(sent: Sent) -> Pid {
  case sent {
    ToService(pid:) -> pid
    ToWorker(pid:) -> pid
  }
}

/// Ends the worker an ask went to, so no work goes on for an asker that gave
/// up; a service is left running.
fn end_worker(sent: Sent) -> Nil {
  case sent {
    ToWorker(pid:) -> {
      exit_process(pid, Shutdown)
      Nil
    }
    ToService(..) -> Nil
  }
}

/// Keeps an ask's tag and monitor until its target answers or ends.
fn keep(
  running running: Running(settings, state, message, answer, outgoing, request),
  tag tag: Reference,
  ask ask: AskId,
  monitor monitor: Reference,
) -> Running(settings, state, message, answer, outgoing, request) {
  Running(..running, kept: dict.insert(running.kept, tag, Kept(ask:, monitor:)))
}

/// The deadline a stopping rule is given: the shutdown time from now, less
/// the send deadline, since Ranch's timer started when it sent the stop and
/// the shell may then have been in a write, which waits at most the send
/// deadline before its socket closes. So the deadline is never later than
/// the moment Ranch kills the process.
fn stop_deadline(
  now: step.Now,
  settings: Settings(settings, state, message, answer, outgoing, request),
) -> Int {
  now.monotonic_ms + settings.shutdown_ms - settings.send_deadline_ms
}

/// Closes the socket, ends the recording and lets the process end normally.
fn stop(
  running: Running(settings, state, message, answer, outgoing, request),
) -> Nil {
  close(running.socket)
  case running.writer {
    None -> Nil
    Some(writer) ->
      case file.finish(writer) {
        Ok(Nil) -> Nil
        Error(error) -> log_recording_failure(error)
      }
  }
}

/// Ends the connection before the step's effects, since its input could not
/// be recorded.
fn recording_failed(socket: ClientSocket, error: FileError) -> a {
  log_recording_failure(error)
  close(socket)
  panic as "a connection's recording could not be written"
}

fn log_recording_failure(error: FileError) -> Nil {
  log(
    LogError,
    "the recording " <> error.path <> " could not be written: " <> error.reason,
    no_one(),
  )
}

/// Ends the connection over an effect the shell does not carry out yet.
fn not_built(socket: ClientSocket, effect: String) -> a {
  log(
    LogError,
    "a rule returned "
      <> effect
      <> ", which the connection shell does not carry out",
    no_one(),
  )
  close(socket)
  panic as "a rule returned an effect the connection shell does not carry out"
}

fn no_one() -> About {
  About(
    connection: None,
    peer: None,
    account_id: None,
    character_id: None,
    map: None,
    message: None,
  )
}

fn now() -> step.Now {
  Now(monotonic_ms: monotonic_ms(), filetime: filetime())
}

@external(erlang, "connection_shell_ffi", "handshake")
fn handshake(ranch_ref: Dynamic, send_deadline_ms: Int) -> ClientSocket

@external(erlang, "connection_shell_ffi", "read_once")
fn read_once(socket: ClientSocket) -> Result(Nil, SocketFailure)

@external(erlang, "connection_shell_ffi", "next_event")
fn next_event(
  socket: ClientSocket,
  parent: Pid,
  kept: Dict(Reference, Kept),
) -> Arrived

@external(erlang, "connection_shell_ffi", "watch")
fn watch(pid: Pid) -> Reference

@external(erlang, "connection_shell_ffi", "unwatch")
fn unwatch(monitor: Reference) -> Nil

@external(erlang, "connection_shell_ffi", "send_answer")
fn send_answer(shell: Pid, tag: Reference, answer: answer) -> Nil

@external(erlang, "connection_shell_ffi", "await_answer")
fn await_answer(
  tag: Reference,
  monitor: Reference,
  parent: Pid,
  deadline_ms: Int,
) -> Waited(answer)

@external(erlang, "erlang", "exit")
fn exit_process(pid: Pid, reason: ExitReason) -> Bool

@external(erlang, "connection_shell_ffi", "send")
fn send(socket: ClientSocket, bytes: BitArray) -> Result(Nil, SocketFailure)

@external(erlang, "connection_shell_ffi", "close")
fn close(socket: ClientSocket) -> Nil

@external(erlang, "connection_shell_ffi", "peer")
fn peer(socket: ClientSocket) -> Peer

@external(erlang, "connection_shell_ffi", "unique_id")
fn unique_id() -> Int

@external(erlang, "connection_shell_ffi", "monotonic_ms")
fn monotonic_ms() -> Int

@external(erlang, "connection_shell_ffi", "filetime")
fn filetime() -> Int

@external(erlang, "connection_shell_ffi", "log")
fn log(level: LogLevel, text: String, about: About) -> Nil
