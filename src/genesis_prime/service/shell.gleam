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
//// - **Stop.** The process exits with the reason `shutdown`, never `normal`:
////   a supervisor reports a permanent child that exits `normal` while it
////   shuts down as a failure, and restarts one that exits `shutdown` at any
////   other time.
//// - **Effects not carried out.** A service writes to no socket and makes no
////   ask. `Write`, `Send`, `Watch`, `Unwatch`, `StartTimer`, `CancelTimer` and a
////   step that ends in an ask end the process with an error log naming them.

import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/step.{type Rule}
import gleam/erlang/process.{type Name, type Pid}
import gleam/option.{type Option}
import gleam/otp/supervision.{type ChildSpecification}

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

/// The service as a permanent child of a supervisor, with `shutdown_ms` as
/// its shutdown timeout.
pub fn supervised(
  settings: Settings(settings, state, message, outgoing),
) -> ChildSpecification(Nil) {
  todo as "the build follows the shape commit"
}

/// Sends a service the message, for an asker's directory: `Error(Nil)` when
/// no process holds the name, else `ToService` with the pid the asker
/// monitors.
pub fn call(
  name name: Name(Call(message, answer)),
  message message: message,
  reply reply: fn(answer) -> Nil,
) -> Result(Sent, Nil) {
  todo as "the build follows the shape commit"
}
