//// The shell of a service: a named process with no socket that other
//// processes ask, running one rule. Like a connection's shell
//// (genesis_prime/connection/shell), it turns everything that reaches the
//// process into the rule's inputs, carries out the rule's effects in order
//// and decides nothing. It is a gleam_otp actor under a supervisor. This
//// module also holds how an asker reaches a service: the `Call` a service
//// takes and the `Sent` an asker's directory gives back.
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
////   EffectsThenAsk(.., ask) ─▶ call(name, message, reply)
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

import genesis_prime/rule_recording.{Taken}
import genesis_prime/rule_recording/file.{type FileError, type Recorder}
import genesis_prime/step.{
  type About, type Event, type Rule, About, Asked, CallerId, Effects,
  EffectsThenAsk, Input, LogError, Now, Started, Stopping,
}
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// What reaches a service when another process asks it: the message, and
/// how to answer it. `reply` sends the answer to the asker, tagged with the
/// ask, and never fails, so an answer to an asker that has gone is dropped.
/// It holds a function, so it is a shell's type, never a rule's.
pub type Call(message, answer) {
  Call(message: message, reply: fn(answer) -> Nil)
}

/// Where an asker's request went, so the asker knows what to watch and what
/// to do at the deadline.
pub type Sent {
  /// To a long-lived service. At the deadline it is left running, and its
  /// answer may come late.
  ToService(pid: Pid)
  /// To a worker started for this ask alone. At the deadline the asker ends
  /// it, so no work goes on for an asker that gave up, and no answer comes
  /// late.
  ToWorker(pid: Pid)
}

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
    recorder: Option(Recorder(settings)),
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

/// Why a process exits; the atom `shutdown`.
type ExitReason {
  Shutdown
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

/// Sends a service the message, for an asker's directory: `Error(Nil)` when
/// no process holds the name, else `ToService` with the pid the asker
/// monitors.
pub fn call(
  name name: Name(Call(message, answer)),
  message message: message,
  reply reply: fn(answer) -> Nil,
) -> Result(Sent, Nil) {
  case process.named(name) {
    Error(Nil) -> Error(Nil)
    Ok(pid) -> {
      // The wire format of a named subject, sent to the pid found: a service
      // that ends after the lookup drops the message, where a send by name
      // would crash the asker.
      let _sent = send_to(pid, #(name, Call(message:, reply:)))
      Ok(ToService(pid:))
    }
  }
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
  use writer <- result.try(case settings.recorder {
    None -> Ok(None)
    Some(recorder) ->
      file.open(recorder, connection: unique_id())
      |> result.map(Some)
      |> result.map_error(RecordingNotOpened)
  })
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
      now: now(),
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
        now: now(),
        event: Asked(caller: CallerId(number), message:),
      ))
    }
    Exited(exit:) ->
      case exit.pid == running.parent {
        True -> {
          let now = now()
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
  let input = Input(now:, event:)
  let #(state, step) = running.settings.rule.step(running.state, input)
  let writer = case running.writer {
    None -> None
    Some(writer) ->
      case file.append(writer, Taken(input:, step:)) {
        Ok(writer) -> Some(writer)
        Error(error) -> recording_failed(error)
      }
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
          log(line.level, line.text, line.about)
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
  case running.writer {
    None -> Nil
    Some(writer) ->
      case file.finish(writer) {
        Ok(Nil) -> Nil
        Error(error) ->
          log(
            LogError,
            "the recording could not be finished: " <> describe(error),
            no_one(),
          )
      }
  }
  exit_now(Shutdown)
}

/// Ends the process over an effect, or an ask, that a service does not carry
/// out.
fn refused(what: String) -> a {
  log(
    LogError,
    "a rule returned " <> what <> ", which the service shell does not carry out",
    no_one(),
  )
  panic as "a rule returned an effect the service shell does not carry out"
}

fn recording_failed(error: FileError) -> a {
  log(
    LogError,
    "the recording could not be written: " <> describe(error),
    no_one(),
  )
  panic as "a service's recording could not be written"
}

fn explain(failure: StartFailure) -> String {
  case failure {
    NameTaken -> "the service's name is already registered"
    RecordingNotOpened(error:) ->
      "the recording could not be opened: " <> describe(error)
  }
}

fn describe(error: FileError) -> String {
  error.path <> ": " <> error.reason
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

@external(erlang, "erlang", "send")
fn send_to(
  pid: Pid,
  message: #(Name(Call(message, answer)), Call(message, answer)),
) -> Dynamic

/// Raises the exit that ends this process with `reason`; a process that traps
/// exits is not ended by an exit signal it sends itself.
@external(erlang, "erlang", "exit")
fn exit_now(reason: ExitReason) -> a

@external(erlang, "connection_shell_ffi", "unique_id")
fn unique_id() -> Int

@external(erlang, "connection_shell_ffi", "monotonic_ms")
fn monotonic_ms() -> Int

@external(erlang, "connection_shell_ffi", "filetime")
fn filetime() -> Int

@external(erlang, "connection_shell_ffi", "log")
fn log(level: step.LogLevel, text: String, about: About) -> Nil
