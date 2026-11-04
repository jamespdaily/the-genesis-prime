//// The timers a shell keeps for its rule (`genesis_prime/step/timer`). Expected
//// values come from its doc comment: a timer's id is unique among the running
//// timers; a firing whose reference is the current timer's of that id gives the
//// id once and forgets the timer; any other firing, such as one queued before the
//// timer was cancelled or one of an earlier timer of the same id, gives none;
//// cancelling runs the timer's way to cancel.

import genesis_prime/step.{TimerId}
import genesis_prime/step/timer
import gleam/erlang/process
import gleam/erlang/reference.{type Reference}
import owned_test

/// Starts the timer, handing the test the reference its firing would carry and
/// a signal when it is cancelled.
fn started(
  timers timers: timer.Timers,
  references references: process.Subject(Reference),
  cancelled cancelled: process.Subject(Nil),
) -> Result(timer.Timers, Nil) {
  timer.start(timers:, timer: TimerId(1), schedule: fn(reference) {
    process.send(references, reference)
    fn() { process.send(cancelled, Nil) }
  })
}

pub fn a_firing_queued_before_a_cancel_is_dropped_and_the_restarted_timers_own_firing_is_taken_once_test() -> Nil {
  use <- owned_test.run(5000)
  let references = process.new_subject()
  let cancelled = process.new_subject()
  let assert Ok(timers) = started(timers: timer.new(), references:, cancelled:)
    as "a timer starts under a free id"
  let assert Ok(old) = process.receive(references, within: 0)
  assert started(timers:, references:, cancelled:) == Error(Nil)
    as "a second timer under a running id is refused"
  let timers = timer.cancel(timers:, timer: TimerId(1))
  assert process.receive(cancelled, within: 0) == Ok(Nil)
    as "cancelling runs the timer's way to cancel"
  let assert Ok(timers) = started(timers:, references:, cancelled:)
    as "the id is free again after the cancel"
  let assert Ok(current) = process.receive(references, within: 0)
  assert timer.fired(timers:, timer: TimerId(1), reference: old) == Error(Nil)
    as "the firing the cancelled timer had queued is not the current timer's"
  let assert Ok(timers) =
    timer.fired(timers:, timer: TimerId(1), reference: current)
    as "the current timer's firing is taken"
  assert timer.fired(timers:, timer: TimerId(1), reference: current)
    == Error(Nil)
    as "and the timer is forgotten, so it fires once"
  assert started(timers:, references:, cancelled:) |> result_ok
    as "a fired timer's id is free"
}

fn result_ok(found: Result(timer.Timers, Nil)) -> Bool {
  case found {
    Ok(_) -> True
    Error(Nil) -> False
  }
}
