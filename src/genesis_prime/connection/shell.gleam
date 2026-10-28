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
////   the registry, when the settings hold one: the shell joins the group of
////     Connection(id), so other processes find it (genesis_prime/connection/registry)
////   Socket(Accepted(connection id, peer, seed))  ─▶ step ─▶ effects
////   loop, the socket active once:
////     {tcp, bytes}        ─▶ Socket(Read(bytes))   ─▶ step ─▶ effects
////     {woken, message}    ─▶ Woken(message)        ─▶ step ─▶ effects
////     a watched process's DOWN ─▶ WatchEnded(id)   ─▶ step ─▶ effects
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
//// - **A message delivered.** Another process sends the connection's pid
////   `{woken, message}` (`registry.deliver`); the shell takes it between steps
////   as `Woken(message)`, in the order it arrived among the socket's reads. One
////   that arrives during an ask waits until the ask's outcome and the step it
////   starts are done, like a read. A message for a connection that has ended is
////   dropped by the VM, and one that arrives after the shell began to stop is
////   dropped with the process. A connection with no registry in its settings is
////   joined to no group, so no process can send it anything.
//// - **A watch.** `Watch(id, target)` finds the target's pid with the settings'
////   `locate`, monitors it and keeps the monitor under `id`
////   (genesis_prime/step/watch). Its DOWN is taken between steps as
////   `WatchEnded(id)`, once, and the shell forgets the watch. A target no
////   process holds comes back as `WatchEnded(id)` as the next input once the
////   step is done, and after the outcome of an ask the step ends in, since
////   no other input is taken meanwhile. `Unwatch(id)` drops the monitor and the
////   DOWN already waiting. A watch's DOWN that arrives during an ask waits like
////   a delivered message. An id already open ends the connection with an error
////   log.
//// - **A timer.** `StartTimer(id, ms)` starts an `erlang:send_after` that sends
////   the shell `{timer_fired, id, reference}`, kept under `id` with its own
////   reference. It is taken between steps as `TimerFired(id)`, once, and the
////   shell forgets the timer; one that fires during an ask waits like a
////   delivered message. `CancelTimer(id)` cancels it and flushes its message if
////   it had fired, so no `TimerFired` follows; a message already in flight
////   when it is cancelled is discarded on arrival, as is any message whose
////   reference is not the current timer's of that id, so a cancelled timer's
////   message never fires a restarted timer of the same id. An id with no
////   running timer is cancelled to nothing. An id already running ends the
////   connection with an error log.
//// - **The registry's scope ending.** The connection stays joined only as long
////   as the scope lives; the tree restarts the game listener with the scope, so
////   no connection outlives it (genesis_prime/connection/registry).
//// - **Effects a connection does not carry out.** `Reply` (a connection is
////   never asked) and `Send` (no connection rule sends): the shell logs an
////   error naming the effect and ends the connection.

import genesis_prime/connection/registry.{type Registry}
import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/service.{type Locate, type Sent, ToService, ToWorker}
import genesis_prime/step.{
  type Ask, type AskId, type ConnectionId, type Effect, type Event, type Peer,
  type Rule, type SocketFailure, type TimerId, Accepted, Answer, Answered,
  AnsweredLate, ConnectionId, Effects, EffectsThenAsk, EndedBeforeAnswer,
  LogError, LogWarning, NoAnswerInTime, NotRunning, PeerClosed, ReadFailed,
  Socket, StoppedWaiting, Stopping, WriteFailed,
}
import genesis_prime/step/runtime.{Shutdown}
import genesis_prime/step/watch.{type Watches}
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Monitor, type Pid}
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

/// A client socket, owned by its connection's process.
type ClientSocket

/// What reaches the process between steps, as `connection_shell_ffi` sees it.
type Arrived(message) {
  Read(bytes: BitArray)
  ClosedByPeer
  FailedToRead(failure: SocketFailure)
  StopRequested
  /// The answer of a kept ask, by its tag.
  LateAnswer(tag: Reference)
  /// The end of a kept ask's target, by the ask's tag.
  KeptEnded(tag: Reference)
  /// Another process sent the connection a message.
  Delivered(message: message)
  /// The end of a monitored process that is no kept ask's, by its monitor.
  WatchedEnded(monitor: Monitor)
  /// A timer fired: its message names the timer's id and the reference of the
  /// start it came from.
  TimerElapsed(timer: TimerId, reference: Reference)
}

/// A timer the shell started: what `erlang:send_after` returned.
type Timer

/// A running timer and the reference its message carries, which tells its
/// timeout from a stale one of an earlier timer of the same id.
type Started {
  Started(timer: Timer, reference: Reference)
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
  Kept(ask: AskId, monitor: Monitor)
}

/// A running connection: its socket, its parent, its settings, the rule's
/// state, the recording file when there is one, the asks kept by their tags,
/// the monitor of each watch the rule has open, each timer it has running and
/// the stop deadline of a stop that arrived during an ask.
type Running(settings, state, message, answer, outgoing, request) {
  Running(
    socket: ClientSocket,
    parent: Pid,
    settings: Settings(settings, state, message, answer, outgoing, request),
    state: state,
    writer: Option(file.Writer),
    kept: Dict(Reference, Kept),
    watches: Watches,
    timers: Dict(TimerId, Started),
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
  let writer = case
    file.open_if(settings.recorder, settings.rule, connection:)
  {
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
      watches: watch.new(),
      timers: dict.new(),
      stopping: None,
    )
  join_registry(settings.registry, ConnectionId(connection))
  take(
    running:,
    now: runtime.now(),
    event: Socket(Accepted(
      connection: ConnectionId(connection),
      peer: peer(socket),
      seed: crypto.strong_random_bytes(32),
    )),
  )
}

/// Folds one input through the rule, records it, then carries out the step.
fn take(
  running running: Running(settings, state, message, answer, outgoing, request),
  now now: step.Now,
  event event: Event(message, answer),
) -> Nil {
  let #(state, step, writer) = case
    file.fold(
      rule: running.settings.rule,
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
        step.Watch(watch:, target:) ->
          carry(
            running: open_watch(running:, watch:, target:),
            effects: later,
            then:,
          )
        step.Unwatch(watch:) ->
          carry(running: close_watch(running:, watch:), effects: later, then:)
        step.StartTimer(timer:, after_ms:) ->
          carry(
            running: start_timer_for(running:, timer:, after_ms:),
            effects: later,
            then:,
          )
        step.CancelTimer(timer:) ->
          carry(
            running: cancel_timer_of(running:, timer:),
            effects: later,
            then:,
          )
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
      process.demonitor_process(monitor)
      take(
        running: Running(..running, kept: dict.delete(running.kept, tag)),
        now:,
        event: AnsweredLate(ask:),
      )
    }
    KeptEnded(tag:) ->
      next(Running(..running, kept: dict.delete(running.kept, tag)))
    Delivered(message:) -> take(running:, now:, event: step.Woken(message:))
    WatchedEnded(monitor:) -> watch_ended(running:, now:, monitor:)
    TimerElapsed(timer:, reference:) ->
      case dict.get(running.timers, timer) {
        Ok(Started(reference: current, ..)) if current == reference ->
          take(
            running: Running(
              ..running,
              timers: dict.delete(running.timers, timer),
            ),
            now:,
            event: step.TimerFired(timer:),
          )
        Ok(Started(..)) | Error(Nil) -> next(running)
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

/// Monitors the process the address names under the watch's id.
fn open_watch(
  running running: Running(settings, state, message, answer, outgoing, request),
  watch watch: step.WatchId,
  target target: step.Address,
) -> Running(settings, state, message, answer, outgoing, request) {
  Running(
    ..running,
    watches: watch.open(
      watches: running.watches,
      watch:,
      target: running.settings.locate(target),
      shell: "connection shell",
    ),
  )
}

/// Drops the watch's monitor, and the DOWN already waiting for it.
fn close_watch(
  running running: Running(settings, state, message, answer, outgoing, request),
  watch watch: step.WatchId,
) -> Running(settings, state, message, answer, outgoing, request) {
  Running(..running, watches: watch.close(watches: running.watches, watch:))
}

/// Takes the end of a watched process as `WatchEnded` with the id of its
/// watch; the DOWN of a monitor the shell holds under no watch is dropped.
fn watch_ended(
  running running: Running(settings, state, message, answer, outgoing, request),
  now now: step.Now,
  monitor monitor: Monitor,
) -> Nil {
  case watch.ended(watches: running.watches, monitor:) {
    Ok(#(watch, watches)) ->
      take(
        running: Running(..running, watches:),
        now:,
        event: step.WatchEnded(watch:),
      )
    Error(Nil) -> next(running)
  }
}

/// Starts the timer the rule named; an id already running ends the connection.
fn start_timer_for(
  running running: Running(settings, state, message, answer, outgoing, request),
  timer timer: TimerId,
  after_ms after_ms: Int,
) -> Running(settings, state, message, answer, outgoing, request) {
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
      let #(started, reference) = start_timer(timer, after_ms)
      Running(
        ..running,
        timers: dict.insert(
          running.timers,
          timer,
          Started(timer: started, reference:),
        ),
      )
    }
  }
}

/// Cancels the timer the rule named, and drops its message if it had fired. A
/// message already in flight is discarded when it arrives, by its reference.
fn cancel_timer_of(
  running running: Running(settings, state, message, answer, outgoing, request),
  timer timer: TimerId,
) -> Running(settings, state, message, answer, outgoing, request) {
  case dict.get(running.timers, timer) {
    Ok(Started(timer: started, reference:)) -> {
      cancel_timer(timer, started, reference)
      Running(..running, timers: dict.delete(running.timers, timer))
    }
    Error(Nil) -> running
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
  case running.settings.directory(ask.request, ask.deadline_ms, reply) {
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
  let monitor = process.monitor(target(sent))
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
      process.send_abnormal_exit(pid, Shutdown)
    }
    ToService(..) -> Nil
  }
}

/// Keeps an ask's tag and monitor until its target answers or ends.
fn keep(
  running running: Running(settings, state, message, answer, outgoing, request),
  tag tag: Reference,
  ask ask: AskId,
  monitor monitor: Monitor,
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
  runtime.finish_recording(running.writer)
}

/// Ends the connection before the step's effects, since its input could not
/// be recorded.
fn recording_failed(socket: ClientSocket, error: FileError) -> a {
  runtime.log_recording_failure(error)
  close(socket)
  panic as "a connection's recording could not be written"
}

/// Ends the connection over an effect the shell does not carry out yet.
fn not_built(socket: ClientSocket, effect: String) -> a {
  close(socket)
  runtime.unsupported(shell: "connection shell", what: effect)
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
) -> Arrived(message)

@external(erlang, "connection_shell_ffi", "start_timer")
fn start_timer(timer: TimerId, after_ms: Int) -> #(Timer, Reference)

@external(erlang, "connection_shell_ffi", "cancel_timer")
fn cancel_timer(timer: TimerId, started: Timer, of: Reference) -> Nil

@external(erlang, "connection_shell_ffi", "send_answer")
fn send_answer(shell: Pid, tag: Reference, answer: answer) -> Nil

@external(erlang, "connection_shell_ffi", "await_answer")
fn await_answer(
  tag: Reference,
  monitor: Monitor,
  parent: Pid,
  deadline_ms: Int,
) -> Waited(answer)

@external(erlang, "connection_shell_ffi", "send")
fn send(socket: ClientSocket, bytes: BitArray) -> Result(Nil, SocketFailure)

@external(erlang, "connection_shell_ffi", "close")
fn close(socket: ClientSocket) -> Nil

@external(erlang, "connection_shell_ffi", "peer")
fn peer(socket: ClientSocket) -> Peer
