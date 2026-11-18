//// The shell of one kept save: a gleam_otp actor, a temporary child of the
//// leaving saver's factory supervisor (genesis_prime/leaving_saver), that runs
//// one rule (genesis_prime/leaving_saver/rule) and decides nothing. It turns
//// what reaches the process into the rule's inputs and carries out the rule's
//// effects in order.
////
//// ```
//// the supervisor starts it with the hand-over ─▶ the actor traps exits, reads the clock
////   Started                                         ─▶ step ─▶ effects
////   Ask(request, within_ms): settings.ask(request, reply) ─▶ Ok(sent): monitors the worker,
////                              starts the ask's deadline timer
////                                                 ─▶ Error(Nil): Answered(Failed(NotRunning))
////   the worker's tagged reply   ─▶ Answered(Stored(..)) | Answered(Failed(Unavailable)) | Answered(Unexpected)
////   the worker's DOWN           ─▶ Answered(Failed(EndedBeforeAnswer))
////   the ask's deadline timer    ─▶ ends the worker (service.end_worker) ─▶ Answered(Failed(NoAnswerInTime))
////   Wait(after_ms): starts the retry timer; its firing ─▶ WaitEnded
////   the parent's exit           ─▶ Stopping
////   Finish                      ─▶ the actor ends normally
//// ```
////
//// - **One timer slot.** An attempt is either in flight or waiting, so the ask's
////   deadline and the retry wait share one slot; a firing of another reference
////   is dropped (genesis_prime/step/timer).
//// - **A reply carries its try's tag.** A late reply of an ended try is dropped.
//// - **The parent's exit is only `Stopping`.** The rule ignores it, so the actor
////   goes on to its own deadline, inside the supervisor's shutdown time; the
////   supervisor's kill after that is the backstop and loses the save.
//// - **The ask is injected.** `Settings.ask` is the store's directory arm
////   (`worker.ask(store, _, _)`); a test passes a stub, and a whole-server test a
////   gate (`server.LeavingSaver.ask_through`).

import genesis_prime/game/leaving_save.{type Handover, type Retries}
import genesis_prime/service.{type Sent}
import genesis_prime/service/shell.{type ServiceTime}
import genesis_prime/store.{type Answer, type Request}
import gleam/erlang/process.{type Name}
import gleam/otp/actor
import gleam/otp/factory_supervisor

/// How a kept save asks the store: the request, and the function that carries
/// the answer back to the asker. `Error(Nil)` when no process runs the store.
pub type Ask =
  fn(Request, fn(Answer) -> Nil) -> Result(Sent, Nil)

/// What the saver is started with.
pub type Settings {
  Settings(
    /// The saver's factory supervisor.
    name: Name(factory_supervisor.Message(Handover, Nil)),
    /// How the save asks the store.
    ask: Ask,
    /// The ladder and the window of every kept save.
    retries: Retries,
    /// How long one ask may take.
    ask_deadline_ms: Int,
    /// How long the supervisor gives its actors to stop: the window plus one
    /// second.
    shutdown_ms: Int,
    /// Where the actors read the time and start their timers.
    time: ServiceTime,
  )
}

/// Starts the actor for one hand-over, as the factory supervisor's start
/// function.
pub fn start(
  settings _settings: Settings,
  handover _handover: Handover,
) -> actor.StartResult(Nil) {
  panic as "the shell is built in the build phase"
}
