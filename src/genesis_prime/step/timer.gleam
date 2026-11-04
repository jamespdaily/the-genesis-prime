//// The timers a service shell keeps for its rule: each `StartTimer` is held
//// under the rule's `TimerId` with the reference its firing carries and the way
//// to cancel it, so a firing that was cancelled, or belongs to an earlier timer
//// of the same id, is told from the current one and dropped.
////
//// - **Start.** A timer's id is unique among the running timers: starting one
////   that runs is a bug, and the shell ends the process with an error log.
//// - **Fired.** A firing whose reference is the current timer's of that id gives
////   the id once and forgets the timer; any other firing gives none.
//// - **Cancel.** The timer's way to cancel runs and the timer is forgotten, so a
////   firing already sent is dropped when it arrives; an id with no running timer
////   is cancelled to nothing.

import genesis_prime/step.{type TimerId}
import gleam/dict.{type Dict}
import gleam/erlang/reference.{type Reference}

/// Ends a timer that was started.
pub type Cancel =
  fn() -> Nil

/// A timer the shell started: how to cancel it, and the reference its firing
/// carries.
type Started {
  Started(cancel: Cancel, reference: Reference)
}

/// The running timers of one shell.
pub opaque type Timers {
  Timers(running: Dict(TimerId, Started))
}

/// No timer running.
pub fn new() -> Timers {
  Timers(running: dict.new())
}

/// Whether a timer is running under the id.
pub fn is_running(timers timers: Timers, timer timer: TimerId) -> Bool {
  dict.has_key(timers.running, timer)
}

/// The timers with one more running under `timer`, whose firing carries
/// `reference` and which `cancel` ends. The shell checks `is_running` first.
pub fn started(
  timers timers: Timers,
  timer timer: TimerId,
  reference reference: Reference,
  cancel cancel: Cancel,
) -> Timers {
  Timers(running: dict.insert(
    timers.running,
    timer,
    Started(cancel:, reference:),
  ))
}

/// The timers without `timer`, which is cancelled; unchanged when none runs
/// under the id.
pub fn cancel(timers timers: Timers, timer timer: TimerId) -> Timers {
  case dict.get(timers.running, timer) {
    Ok(Started(cancel:, ..)) -> {
      cancel()
      Timers(running: dict.delete(timers.running, timer))
    }
    Error(Nil) -> timers
  }
}

/// The timers without `timer`, when the firing with this `reference` is the
/// current timer's; `Error(Nil)` for any other firing, which the shell drops.
pub fn fired(
  timers timers: Timers,
  timer timer: TimerId,
  reference reference: Reference,
) -> Result(Timers, Nil) {
  case dict.get(timers.running, timer) {
    Ok(Started(reference: current, ..)) if current == reference ->
      Ok(Timers(running: dict.delete(timers.running, timer)))
    Ok(Started(..)) | Error(Nil) -> Error(Nil)
  }
}
