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
////   Socket(Accepted(connection id, peer, seed))  ─▶ step ─▶ effects
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
////   A step that follows `StoppedWaiting` and ends in another ask gets
////   `Answered(_, StoppedWaiting)` at once, with no call to the directory, so
////   every ask has one `Answered`; `Stopping` is the next input after a step
////   that ends without an ask. A worker answers late only when its answer left
////   before the shell's exit reached it. The `Now` of `Answered` is read when the outcome is known.
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
  type Ask, type AskId, type Effect, type Event, type Peer, type Rule,
  type SocketFailure, Accepted, Answer, Answered, AnsweredLate, ConnectionId,
  Effects, EffectsThenAsk, EndedBeforeAnswer, Input, LogError, LogWarning,
  NoAnswerInTime, NotRunning, PeerClosed, ReadFailed, Socket, StoppedWaiting,
  Stopping, WriteFailed,
}
import genesis_prime/step/runtime
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
  let connection = runtime.unique_id()
  let writer = case file.open_if(settings.recorder, connection:) {
    Ok(writer) -> writer
    Error(error) -> recording_failed(socket, error)
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
    now: runtime.now(),
    event: Socket(Accepted(
      connection: ConnectionId(connection),
      peer: peer(socket),
      seed: seed(),
    )),
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
  let writer = case file.append_if(running.writer, Taken(input:, step:)) {
    Ok(writer) -> writer
    Error(error) -> recording_failed(running.socket, error)
  }
  let running = Running(..running, state:, writer:)
  case step {
    Effects(effects:) -> carry(running:, effects:, then: WaitForInput)
    EffectsThenAsk(effects:, ask:) ->
      carry(running:, effects:, then: MakeAsk(ask))
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
/// out, then the process ends. A failed write after a `Stop` closes the socket
/// and ends the process, without a `WriteFailed` input, since the rule asked
/// to end. When a stop arrived during an earlier ask, a step that ends in an
/// ask gets `Answered(_, StoppedWaiting)` at once without the directory being
/// called, and the stop is the next input after a step that ends without an
/// ask.
fn carry(
  running running: Running(settings, state, message, answer, outgoing, request),
  effects effects: List(Effect(outgoing)),
  then then: Then(request),
) -> Nil {
  case effects {
    [] ->
      case then, running.stopping {
        EndProcess, _ -> stop(running)
        MakeAsk(ask:), None -> make_ask(running, ask)
        MakeAsk(ask:), Some(_) ->
          take(
            running:,
            now: runtime.now(),
            event: Answered(ask: ask.ask, outcome: StoppedWaiting),
          )
        WaitForInput, None -> wait(running)
        WaitForInput, Some(deadline_ms) ->
          take(
            running: Running(..running, stopping: None),
            now: runtime.now(),
            event: Stopping(deadline_ms:),
          )
      }
    [effect, ..later] ->
      case effect {
        step.Write(bytes:) ->
          case send(running.socket, bytes), then {
            Ok(Nil), _ -> carry(running:, effects: later, then:)
            Error(failure), EndProcess -> {
              runtime.log(
                LogWarning,
                "a write after the rule's Stop failed ("
                  <> step.describe_socket_failure(failure)
                  <> "), so the connection ends",
                step.no_one,
              )
              stop(running)
            }
            Error(failure), MakeAsk(..) | Error(failure), WaitForInput ->
              take(
                running:,
                now: runtime.now(),
                event: Socket(WriteFailed(failure:)),
              )
          }
        step.Log(line:) -> {
          runtime.log(line.level, line.text, line.about)
          carry(running:, effects: later, then:)
        }
        step.Stop -> carry(running:, effects: later, then: EndProcess)
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
      take(running:, now: runtime.now(), event: Socket(ReadFailed(failure:)))
    Ok(Nil) -> next(running)
  }
}

/// Takes what reaches the process next as an input. The end of a kept ask's
/// target is no input; it only drops the tag.
fn next(
  running: Running(settings, state, message, answer, outgoing, request),
) -> Nil {
  let arrived = next_event(running.socket, running.parent, running.kept)
  let now = runtime.now()
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
        now: runtime.now(),
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
  let known = runtime.now()
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
  case file.finish_if(running.writer) {
    Ok(Nil) -> Nil
    Error(error) -> log_recording_failure(error)
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
  runtime.log(
    LogError,
    "the recording could not be written: " <> file.describe(error),
    step.no_one,
  )
}

/// Ends the connection over an effect the shell does not carry out yet.
fn not_built(socket: ClientSocket, effect: String) -> a {
  runtime.log(
    LogError,
    "a rule returned "
      <> effect
      <> ", which the connection shell does not carry out",
    step.no_one,
  )
  close(socket)
  panic as "a rule returned an effect the connection shell does not carry out"
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

/// 32 bytes from the operating system's strong random source, the seed of a
/// new connection.
@external(erlang, "connection_shell_ffi", "seed")
fn seed() -> BitArray
