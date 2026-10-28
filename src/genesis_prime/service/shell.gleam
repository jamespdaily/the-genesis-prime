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
//// - **Effects not carried out.** A service writes to no socket and makes no
////   ask. `Write`, `Send`, `Watch`, `Unwatch`, `StartTimer`, `CancelTimer` and a
////   step that ends in an ask end the process with an error log naming them.

import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/service.{type Call, Call}
import genesis_prime/step.{
  type Event, type Rule, Asked, CallerId, Effects, EffectsThenAsk, Started,
  Stopping,
}
import genesis_prime/step/runtime.{type ExitReason, Shutdown}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Pid}
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
}

/// A running service: its settings, its parent, the rule's state, the
/// recording file when there is one, and the calls not yet answered by the
/// number the shell gave each.
type Running(settings, state, message, outgoing) {
  Running(
    settings: Settings(settings, state, message, outgoing),
    parent: Pid,
    state: state,
    writer: Option(file.Writer),
    callers: Dict(Int, fn(outgoing) -> Nil),
    next_caller: Int,
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
      ),
      now: runtime.now(),
      event: Started,
    )
  let selector =
    process.new_selector()
    |> process.select_map(process.named_subject(settings.name), Called)
    |> process.select_trapped_exits(Exited)
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
        step.Send(..) -> refused("Send")
        step.Watch(..) -> refused("Watch")
        step.Unwatch(..) -> refused("Unwatch")
        step.StartTimer(..) -> refused("StartTimer")
        step.CancelTimer(..) -> refused("CancelTimer")
      }
  }
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
