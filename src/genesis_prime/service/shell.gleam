//// The shell of a service: a process with no socket that other processes
//// ask, running one rule. A singleton (the hand-off, Sessions) registers a
//// name; a map is one of many and registers none: Maps holds the subject
//// its start returns (genesis_prime/world_map/maps), since a name is an atom
//// and maps come and go. Like a connection's shell
//// (genesis_prime/connection/shell), it turns everything that reaches the
//// process into the rule's inputs, carries out the rule's effects in order
//// and decides nothing. It is a gleam_otp actor under a supervisor. How an
//// asker reaches a service, the `Call` a service takes, is in
//// genesis_prime/service.
////
//// One service, from start to end:
////
//// ```
//// supervisor starts it ─▶ the actor registers its name, traps exits
////   the recorder, when on, opens the file and writes the header
////   OwnEvent(Started)                               ─▶ step ─▶ effects
////   after each step's effects, before the mailbox is read:
////     a watch of a target no process holds ─▶ WatchEnded(id) ─▶ step ─▶ effects
////   loop:
////     Call(message, reply)  ─▶ OwnEvent(Asked(CallerId(n), message)) ─▶ step ─▶ effects
////     a watched process's DOWN ─▶ WatchEnded(id)           ─▶ step ─▶ effects
////     the parent's exit     ─▶ Stopping(now + shutdown_ms) ─▶ step ─▶ effects
////   Reply(CallerId(n), answer): the shell calls that call's reply with the
////     answer and forgets the caller
////   each step: the recorder writes Taken(input, step) before its effects
//// ```
////
//// An ask, from the asker's side (the connection shell carries it out):
////
//// ```
//// asker                         directory                 service
////   EffectsThenAsk(.., ask) ─▶ service.call(name, message, reply)
////                                 name not registered ─▶ Error(Nil): NotRunning
////                                 else monitor, send ──▶ Call(message, reply)
////   waits until the ask's deadline                          Asked ─▶ step
////   ◀── {ask answer, tag, answer} ◀─────────────────────────── Reply
////   Answered(ask, Answer(answer))
//// ```
////
//// - **CallerId.** The shell numbers the calls it takes from 1, in the order
////   they arrive, so a recording names each caller with no process id.
////   reaches the asker's shell, which drops it with no input to the asker's
////   rule (genesis_prime/connection/shell); one to an asker that has ended is
////   lost. The service never knows either way.
//// - **A crash.** The rule's crash ends the process; the supervisor restarts
////   it from the rule's `new`, so the service's state is lost. An asker
////   waiting on it gets `EndedBeforeAnswer`; one asking while it restarts gets
////   `NotRunning`.
//// - **The server stopping.** The shell traps exits, so the supervisor's stop
////   arrives as `Stopping`, with a deadline of the child's shutdown time from
////   when it arrived. A rule that has not stopped by then is killed.
//// - **Stop.** The shell carries out the step's other effects, then the
////   process exits with the reason `shutdown`, never `normal`:
////   a supervisor reports a permanent child that exits `normal` while it
////   shuts down as a failure, and restarts one that exits `shutdown` at any
////   other time. A watch's end held by a step that stops the process is
////   not taken, since the process has ended.
//// - **Send.** `Send(to, message)` looks `to` up with the settings' `reach` and
////   hands the message to the process found, in the form its shell takes (a
////   connection takes it as `Woken`). An address with no process running
////   drops the message, with no input and no log line: a rule that must know
////   watches the receiver.
//// - **Watch.** `Watch(id, target)` finds `target` with the settings' `locate`
////   and monitors it, keeping the monitor under `id` in the shell. The target's
////   end comes back once as `WatchEnded(id)` and the shell forgets the watch. A
////   target no process holds when the watch begins is monitored by nothing:
////   the shell holds the id, and takes `WatchEnded(id)` as its next input
////   once the step's effects are carried out, before it reads its mailbox,
////   with the ends of the step's other such watches in the order opened (a
////   rule's step that those inputs start takes its own the same way); one
////   that ends between the lookup and the monitor fires the monitor at once. A
////   rule's id that is already open, monitored or held, ends the process with
////   an error log: an id is unique among the open watches (genesis_prime/step/watch).
//// - **Unwatch.** `Unwatch(id)` drops the monitor of `id` and flushes its DOWN
////   from the mailbox, or drops an id held for a target no process holds, so
////   no `WatchEnded` follows; an id with no open watch does nothing.
//// - **A watch's end and a restart.** A watch lives in the process: a restarted
////   service has no watches, and a rule that needs one opens it again from
////   what it learns of its processes (Sessions has none to open: the
////   connections claim again).
//// - **Effects and inputs of the other kind.** A service's own effects are
////   `Reply` and `Send`, and its own inputs are `Started` and `Asked`
////   (`ServiceEffect` and `ServiceEvent`). It has no `Write`, `StartTimer` or
////   `CancelTimer`, and takes no `Woken`, `TimerFired` or `Answered`, so a rule
////   that writes to a socket, starts a timer or takes those inputs does not
////   compile against this shell. It makes no ask: its request type, `NoAsk`,
////   has no values, so no rule can build a step that ends in one; the shell's
////   case for such a step is unreachable.

/// - **A reply nobody waits for.** An answer after the asker's deadline
import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/service.{type Call, type Reach, Call}
import genesis_prime/step.{
  type Effect, type Event, type ServiceEffect, type ServiceEvent,
  type ServiceRule, type WatchId, Asked, CallerId, Effects, EffectsThenAsk,
  OwnEffect, OwnEvent, Reply, Send, Started, Stopping, WatchEnded,
}
import genesis_prime/step/runtime.{Shutdown}
import genesis_prime/step/watch.{type Watches}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// What a service is started with.
pub type Settings(settings, state, message, outgoing) {
  Settings(
    /// The rule. A service takes no answers and makes no asks, so those
    /// types are `Nil`; `outgoing` is what it answers with.
    rule: ServiceRule(settings, state, message, outgoing),
    /// How it finds the processes its rule watches and sends to.
    reach: Reach(outgoing),
    /// How long it has to stop once the supervisor stops it; the child's
    /// shutdown timeout.
    shutdown_ms: Int,
    /// Where its inputs are recorded; `None` unless the dev start turns
    /// recording on.
    recorder: Option(Recorder),
  )
}

/// What reaches the actor: a call, or an exit signal it traps.
type Mail(message, outgoing) {
  Called(call: Call(message, outgoing))
  Exited(exit: process.ExitMessage)
  /// The end of a process the rule watches, by its monitor.
  Ended(down: process.Down)
}

/// A running service: its settings, its parent, the rule's state, the
/// recording file when there is one, the calls not yet answered by the
/// number the shell gave each, and the monitor of each watch the rule has
/// open.
type Running(settings, state, message, outgoing) {
  Running(
    settings: Settings(settings, state, message, outgoing),
    parent: Pid,
    state: state,
    writer: Option(file.Writer),
    callers: Dict(Int, fn(outgoing) -> Nil),
    next_caller: Int,
    watches: Watches,
  )
}

/// Why a service could not start.
type StartFailure {
  NameTaken
  RecordingNotOpened(error: FileError)
}

/// The service as a permanent child of a supervisor, registered under `name`,
/// with `shutdown_ms` as its shutdown timeout. Askers find it by the name.
pub fn supervised(
  name name: Name(Call(message, outgoing)),
  settings settings: Settings(settings, state, message, outgoing),
) -> ChildSpecification(Nil) {
  // The supervisor runs the start function, so its own pid is the parent.
  supervision.worker(fn() {
    start(settings:, parent: process.self(), name: Some(name))
    |> result.map(fn(started) { actor.Started(pid: started.pid, data: Nil) })
  })
  |> supervision.restart(supervision.Permanent)
  |> supervision.timeout(ms: settings.shutdown_ms)
}

/// Starts a service with no name as a child of the supervisor that runs this
/// function, such as the map supervisor, giving the subject askers send their
/// calls to.
pub fn start_unnamed(
  settings: Settings(settings, state, message, outgoing),
) -> actor.StartResult(Subject(Call(message, outgoing))) {
  start(settings:, parent: process.self(), name: None)
}

fn start(
  settings settings: Settings(settings, state, message, outgoing),
  parent parent: Pid,
  name name: Option(Name(Call(message, outgoing))),
) -> actor.StartResult(Subject(Call(message, outgoing))) {
  actor.new_with_initialiser(5000, fn(_subject) {
    initialise(settings:, parent:, name:) |> result.map_error(explain)
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// Registers the name (a named service) or makes the subject its callers send
/// to (an unnamed one), traps exits, opens the recording and takes `Started`.
fn initialise(
  settings settings: Settings(settings, state, message, outgoing),
  parent parent: Pid,
  name name: Option(Name(Call(message, outgoing))),
) -> Result(
  actor.Initialised(
    Running(settings, state, message, outgoing),
    Mail(message, outgoing),
    Subject(Call(message, outgoing)),
  ),
  StartFailure,
) {
  use calls <- result.try(case name {
    Some(name) ->
      process.register(process.self(), name)
      |> result.replace(process.named_subject(name))
      |> result.replace_error(NameTaken)
    None -> Ok(process.new_subject())
  })
  process.trap_exits(True)
  use writer <- result.try(
    file.open_if(
      settings.recorder,
      settings.rule,
      connection: runtime.unique_id(),
    )
    |> result.map_error(RecordingNotOpened),
  )
  let rule = settings.rule
  let running =
    take(
      running: Running(
        settings:,
        parent:,
        state: rule.new(rule.settings),
        writer:,
        callers: dict.new(),
        next_caller: 1,
        watches: watch.new(),
      ),
      now: runtime.now(),
      event: OwnEvent(Started),
    )
  let selector =
    process.new_selector()
    |> process.select_map(calls, Called)
    |> process.select_trapped_exits(Exited)
    |> process.select_monitors(Ended)
  Ok(
    actor.initialised(running)
    |> actor.selecting(selector)
    |> actor.returning(calls),
  )
}

fn handle(
  running: Running(settings, state, message, outgoing),
  mail: Mail(message, outgoing),
) -> actor.Next(
  Running(settings, state, message, outgoing),
  Mail(message, outgoing),
) {
  case mail {
    Called(Call(message:, reply:)) -> {
      let number = running.next_caller
      let running =
        Running(
          ..running,
          callers: dict.insert(running.callers, number, reply),
          next_caller: number + 1,
        )
      actor.continue(take(
        running:,
        now: runtime.now(),
        event: OwnEvent(Asked(caller: CallerId(number), message:)),
      ))
    }
    Ended(down:) -> actor.continue(watch_ended(running:, down:))
    Exited(exit:) ->
      case exit.pid == running.parent {
        True -> {
          let now = runtime.now()
          actor.continue(take(
            running:,
            now:,
            event: Stopping(
              deadline_ms: now.monotonic_ms + running.settings.shutdown_ms,
            ),
          ))
        }
        False -> actor.continue(running)
      }
  }
}

/// Folds one input through the rule, records it, then carries out the step.
/// The end of each watch of a target no process holds that the step opened is
/// then taken as the next input, in the order opened, before the mailbox is
/// read.
fn take(
  running running: Running(settings, state, message, outgoing),
  now now: step.Now,
  event event: Event(ServiceEvent(message)),
) -> Running(settings, state, message, outgoing) {
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
    Error(error) -> recording_failed(error)
  }
  let running = Running(..running, state:, writer:)
  let running = case step {
    Effects(effects:) -> carry(running:, effects:, ending: False)
    EffectsThenAsk(..) ->
      panic as "a service step ended in an ask, which its request type has no value for"
  }
  case watch.next_unheld_end(running.watches) {
    Ok(#(watch, watches)) ->
      take(
        running: Running(..running, watches:),
        now: runtime.now(),
        event: WatchEnded(watch:),
      )
    Error(Nil) -> running
  }
}

/// Carries out the effects in order. A `Stop` among them does not end the
/// step: the effects after it are carried out, then the process ends.
fn carry(
  running running: Running(settings, state, message, outgoing),
  effects effects: List(Effect(ServiceEffect(outgoing))),
  ending ending: Bool,
) -> Running(settings, state, message, outgoing) {
  case effects {
    [] ->
      case ending {
        True -> stop(running)
        False -> running
      }
    [effect, ..later] ->
      case effect {
        OwnEffect(Reply(caller: CallerId(number), answer:)) ->
          case dict.get(running.callers, number) {
            Ok(reply) -> {
              reply(answer)
              carry(
                running: Running(
                  ..running,
                  callers: dict.delete(running.callers, number),
                ),
                effects: later,
                ending:,
              )
            }
            Error(Nil) ->
              panic as "a rule replied to a caller it was not asked by, or answered one twice"
          }
        step.Log(line:) -> {
          runtime.log(line.level, line.text, line.about)
          carry(running:, effects: later, ending:)
        }
        step.Stop -> carry(running:, effects: later, ending: True)
        OwnEffect(Send(to:, message:)) ->
          carry(
            running: deliver(running:, to:, message:),
            effects: later,
            ending:,
          )
        step.Watch(watch:, target:) ->
          carry(
            running: open_watch(running:, watch:, target:),
            effects: later,
            ending:,
          )
        step.Unwatch(watch:) ->
          carry(running: close_watch(running:, watch:), effects: later, ending:)
      }
  }
}

/// Hands the message to the process at the address, or drops it when no
/// process runs there.
fn deliver(
  running running: Running(settings, state, message, outgoing),
  to to: step.Address,
  message message: outgoing,
) -> Running(settings, state, message, outgoing) {
  let _delivered = running.settings.reach.send(to, message)
  running
}

/// Monitors the process at the address under the watch's id.
fn open_watch(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
  target target: step.Address,
) -> Running(settings, state, message, outgoing) {
  Running(
    ..running,
    watches: watch.open(
      watches: running.watches,
      watch:,
      target: running.settings.reach.locate(target),
      shell: "service shell",
    ),
  )
}

/// Drops the watch's monitor, and the DOWN already waiting for it.
fn close_watch(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
) -> Running(settings, state, message, outgoing) {
  Running(..running, watches: watch.close(watches: running.watches, watch:))
}

/// Takes the end of a watched process as `WatchEnded` with the id of its
/// watch, and forgets the watch; the DOWN of a monitor the shell does not hold
/// is dropped.
fn watch_ended(
  running running: Running(settings, state, message, outgoing),
  down down: process.Down,
) -> Running(settings, state, message, outgoing) {
  let monitor = case down {
    process.ProcessDown(monitor:, ..) | process.PortDown(monitor:, ..) ->
      monitor
  }
  case watch.ended(watches: running.watches, monitor:) {
    Ok(#(watch, watches)) ->
      take(
        running: Running(..running, watches:),
        now: runtime.now(),
        event: WatchEnded(watch:),
      )
    Error(Nil) -> running
  }
}

/// Ends the recording and exits with the reason `shutdown`.
fn stop(running: Running(settings, state, message, outgoing)) -> a {
  runtime.finish_recording(running.writer)
  runtime.exit_now(Shutdown)
}

fn recording_failed(error: FileError) -> a {
  runtime.log_recording_failure(error)
  panic as "a service's recording could not be written"
}

fn explain(failure: StartFailure) -> String {
  case failure {
    NameTaken -> "the service's name is already registered"
    RecordingNotOpened(error:) ->
      "the recording could not be opened: " <> file.describe(error)
  }
}
