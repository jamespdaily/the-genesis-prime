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
////   A worker answers late only when its answer left before the shell's exit
////   reached it. The `Now` of `Answered` is read when the outcome is known.
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
import genesis_prime/service/shell.{type Sent} as service_shell
import genesis_prime/step.{
  type About, type Effect, type Event, type LogLevel, type Peer, type Rule,
  type SocketFailure, About, Accepted, ConnectionId, Effects, EffectsThenAsk,
  Input, LogError, Now, PeerClosed, ReadFailed, Socket, Stopping, WriteFailed,
}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid}
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
}

/// A running connection: its socket, its parent, its settings, the rule's
/// state and the recording file, when there is one.
type Running(settings, state, message, answer, outgoing, request) {
  Running(
    socket: ClientSocket,
    parent: Pid,
    settings: Settings(settings, state, message, answer, outgoing, request),
    state: state,
    writer: Option(file.Writer),
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
    Effects(effects:) -> carry(running, effects)
    EffectsThenAsk(..) -> not_built(running.socket, "an ask")
  }
}

/// Carries out the effects in order, then waits for the next input.
fn carry(
  running: Running(settings, state, message, answer, outgoing, request),
  effects: List(Effect(outgoing)),
) -> Nil {
  case effects {
    [] -> wait(running)
    [effect, ..later] ->
      case effect {
        step.Write(bytes:) ->
          case send(running.socket, bytes) {
            Ok(Nil) -> carry(running, later)
            Error(failure) ->
              take(running:, now: now(), event: Socket(WriteFailed(failure:)))
          }
        step.Log(line:) -> {
          log(line.level, line.text, line.about)
          carry(running, later)
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
    Ok(Nil) -> {
      let arrived = next_event(running.socket, running.parent)
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
      }
    }
  }
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
fn next_event(socket: ClientSocket, parent: Pid) -> Arrived

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
