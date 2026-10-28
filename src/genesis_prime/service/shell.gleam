//// The shell of a service: a named process with no socket that other
//// processes ask, running one rule. Like a connection's shell
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
////   Started                                         ─▶ step ─▶ effects
////   loop:
////     Call(message, reply)  ─▶ Asked(CallerId(n), message) ─▶ step ─▶ effects
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
//// - **A reply nobody waits for.** An answer after the asker's deadline
////   reaches it as `AnsweredLate`; one to an asker that has ended is lost.
////   The service never knows either way.
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
////   other time.
//// - **Send.** `Send(to, message)` looks `to` up with the settings' `reach` and
////   hands the message to the process found, in the form its shell takes (a
////   connection takes it as `Woken`). An address with no process running
////   drops the message, with no input and no log line: a rule that must know
////   watches the receiver.
//// - **Watch.** `Watch(id, target)` finds `target` with the settings' `locate`
////   and monitors it, keeping the monitor under `id` in the shell. The target's
////   end comes back once as `WatchEnded(id)` and the shell forgets the watch. A
////   target no process holds when the watch begins comes back as
////   `WatchEnded(id)` as the next input, after the step's effects are carried
////   out; one that ends between the lookup and the monitor fires the monitor at
////   once. A rule's id that is already open ends the process with an error
////   log: an id is unique among the open watches.
//// - **Unwatch.** `Unwatch(id)` drops the monitor of `id` and flushes its DOWN
////   from the mailbox, so no `WatchEnded` follows; an id with no open watch
////   does nothing.
//// - **A watch's end and a restart.** A watch lives in the process: a restarted
////   service has no watches, and a rule that needs one opens it again from
////   what it learns of its processes (Sessions has none to open: the
////   connections claim again).
//// - **Effects not carried out.** A service writes to no socket and makes no
////   ask. `Write`, `StartTimer`, `CancelTimer` and a step that ends in an ask
////   end the process with an error log naming them.

import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/service.{type Call, type Reach, Call}
import genesis_prime/step.{
  type Event, type Rule, type WatchId, Asked, CallerId, Effects, EffectsThenAsk,
  Started, Stopping,
}
import genesis_prime/step/runtime.{type ExitReason, Shutdown}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Monitor, type Name, type Pid}
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// What a service is started with.
pub type Settings(settings, state, message, outgoing) {
  Settings(
    /// The rule. A service takes no answers and makes no asks, so those
    /// types are `Nil`; `outgoing` is what it answers with.
    rule: Rule(settings, state, message, Nil, outgoing, Nil),
    /// The name it registers, made once at start.
    name: Name(Call(message, outgoing)),
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
    watches: Dict(WatchId, Monitor),
  )
}

/// Why a service could not start.
type StartFailure {
  NameTaken
  RecordingNotOpened(error: FileError)
}

/// The service as a permanent child of a supervisor, with `shutdown_ms` as
/// its shutdown timeout.
pub fn supervised(
  settings: Settings(settings, state, message, outgoing),
) -> ChildSpecification(Nil) {
  // The supervisor runs the start function, so its own pid is the parent.
  supervision.worker(fn() { start(settings, process.self()) })
  |> supervision.restart(supervision.Permanent)
  |> supervision.timeout(ms: settings.shutdown_ms)
}

fn start(
  settings: Settings(settings, state, message, outgoing),
  parent: Pid,
) -> actor.StartResult(Nil) {
  actor.new_with_initialiser(5000, fn(_subject) {
    initialise(settings, parent) |> result.map_error(explain)
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// Registers the name, traps exits, opens the recording and takes `Started`.
fn initialise(
  settings: Settings(settings, state, message, outgoing),
  parent: Pid,
) -> Result(
  actor.Initialised(
    Running(settings, state, message, outgoing),
    Mail(message, outgoing),
    Nil,
  ),
  StartFailure,
) {
  use Nil <- result.try(
    process.register(process.self(), settings.name)
    |> result.replace_error(NameTaken),
  )
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
        watches: dict.new(),
      ),
      now: runtime.now(),
      event: Started,
    )
  let selector =
    process.new_selector()
    |> process.select_map(process.named_subject(settings.name), Called)
    |> process.select_trapped_exits(Exited)
    |> process.select_monitors(Ended)
  Ok(
    actor.initialised(running)
    |> actor.selecting(selector)
    |> actor.returning(Nil),
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
        event: Asked(caller: CallerId(number), message:),
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
fn take(
  running running: Running(settings, state, message, outgoing),
  now now: step.Now,
  event event: Event(message, Nil),
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
  case step {
    Effects(effects:) -> carry(running:, effects:, ending: False)
    EffectsThenAsk(..) -> refused("an ask")
  }
}

/// Carries out the effects in order. A `Stop` among them does not end the
/// step: the effects after it are carried out, then the process ends.
fn carry(
  running running: Running(settings, state, message, outgoing),
  effects effects: List(step.Effect(outgoing)),
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
        step.Reply(caller: CallerId(number), answer:) ->
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
        step.Write(..) -> refused("Write")
        step.Send(to:, message:) ->
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
        step.StartTimer(..) -> refused("StartTimer")
        step.CancelTimer(..) -> refused("CancelTimer")
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
  todo as "the build follows the shape commit"
}

/// Monitors the process at the address under the watch's id.
fn open_watch(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
  target target: step.Address,
) -> Running(settings, state, message, outgoing) {
  todo as "the build follows the shape commit"
}

/// Drops the watch's monitor, and the DOWN already waiting for it.
fn close_watch(
  running running: Running(settings, state, message, outgoing),
  watch watch: WatchId,
) -> Running(settings, state, message, outgoing) {
  todo as "the build follows the shape commit"
}

/// Takes the end of a watched process as `WatchEnded` with the id of its
/// watch, and forgets the watch; the DOWN of a monitor the shell does not hold
/// is dropped.
fn watch_ended(
  running running: Running(settings, state, message, outgoing),
  down down: process.Down,
) -> Running(settings, state, message, outgoing) {
  todo as "the build follows the shape commit"
}

/// Ends the recording and exits with the reason `shutdown`.
fn stop(running: Running(settings, state, message, outgoing)) -> a {
  runtime.finish_recording(running.writer)
  exit_now(Shutdown)
}

/// Ends the process over an effect, or an ask, that a service does not carry
/// out.
fn refused(what: String) -> a {
  runtime.unsupported(shell: "service shell", what:)
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

/// Raises the exit that ends this process with `reason`; a process that traps
/// exits is not ended by an exit signal it sends itself.
@external(erlang, "erlang", "exit")
fn exit_now(reason: ExitReason) -> a
