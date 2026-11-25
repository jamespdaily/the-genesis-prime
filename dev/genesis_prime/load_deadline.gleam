//// The strike deadlines of a load run, recorded as they are armed, closed and fired,
//// with nothing traced and no counter in the server's rules.
////
//// ```
//// a creature's shell ─ StartServiceTimer(StrikeDeadline) ─▶ `recorder`'s scheduler
////                         │ Armed ──────────────────────────────▶ recorder process
////                         │ send_after(recorder, Fired) ────────▶ recorder: stamps the
////                         │                                        firing, then sends the
////                         │                                        shell its `Elapsed`
////                         └ cancel ─ Cancelled ─────────────────▶ recorder
//// ```
////
//// The recorder is the `Scheduler` of the server's `ServiceTime` (the service shell's
//// `schedule`). It gives every timer that is not numbered like a creature's strike
//// deadline (`creature.is_strike_deadline`) to the operating system's timer unchanged;
//// one that is is set to fire at the recorder instead, which stamps the firing and
//// sends the shell its `Elapsed` at once, so the shell takes the same message a moment
//// later. The number does not tell whose the timer is: the map arms a timer numbered by
//// the spawn for its restart, which can carry a deadline's number. So the recorder keeps
//// the process that armed each one (the scheduler runs in the shell), and a caller
//// picks the creatures' by their processes (`of_creature`).
////
//// A deadline's closure is one of: still open, cancelled (the round closed by an
//// answer, a death, a crowd-control state, the leash or an interrupt, which the shell's
//// `CancelServiceTimer` does not tell apart), or fired. A firing the shell cancelled
//// before it took the firing is still told as fired when the recorder had already
//// stamped it: the stamp and the cancel are two messages to the recorder, so the run
//// cannot tell them apart.

import genesis_prime/connection/script.{type Elapsed, type Scheduler, Elapsed}
import genesis_prime/load_sample
import genesis_prime/step.{type TimerId}
import genesis_prime/step/timer
import genesis_prime/world_map/creature
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// How a deadline ended.
pub type Closure {
  Open
  Cancelled(at_us: Int)
  Fired(at_us: Int)
}

/// A timer numbered like a strike deadline: `creature`, the process that armed it (a
/// creature's, when the deadline is), when it was armed, when it falls due, and how it
/// ended, on the monotonic clock in microseconds.
pub type Deadline {
  Deadline(creature: Pid, armed_us: Int, due_us: Int, closure: Closure)
}

/// The recorder's process, which the scheduler and the report talk to.
pub opaque type Recorder {
  Recorder(events: Subject(Event))
}

type Event {
  Armed(reference: Reference, deadline: Deadline)
  Elapsing(reference: Reference, shell: Subject(Elapsed), elapsed: Elapsed)
  Closed(reference: Reference, at_us: Int)
  Collect(reply: Subject(List(Deadline)))
}

/// Starts the recorder's process, unlinked, which runs until the node ends.
pub fn start() -> Recorder {
  let ready = process.new_subject()
  let _pid =
    process.spawn_unlinked(fn() {
      let events = process.new_subject()
      process.send(ready, events)
      record(events:, deadlines: dict.new())
    })
  let assert Ok(events) = process.receive(ready, within: 5000)
    as "the recorder started"
  Recorder(events:)
}

/// The scheduler to give the server's `ServiceTime`: the operating system's timer
/// for every timer not numbered like a creature's strike deadline, which the recorder sees.
pub fn scheduler(recorder recorder: Recorder) -> Scheduler {
  fn(
    shell: Subject(Elapsed),
    timer: TimerId,
    reference: Reference,
    after_ms: Int,
  ) -> timer.Cancel {
    case creature.is_strike_deadline(timer:) {
      False -> script.operating_system_timer(shell, timer, reference, after_ms)
      True -> {
        let armed_us = load_sample.microseconds()
        process.send(
          recorder.events,
          Armed(
            reference:,
            deadline: Deadline(
              creature: process.self(),
              armed_us:,
              due_us: armed_us + after_ms * 1000,
              closure: Open,
            ),
          ),
        )
        let started =
          process.send_after(
            recorder.events,
            after_ms,
            Elapsing(reference:, shell:, elapsed: Elapsed(timer:, reference:)),
          )
        fn() {
          let _cancelled = process.cancel_timer(started)
          process.send(
            recorder.events,
            Closed(reference:, at_us: load_sample.microseconds()),
          )
        }
      }
    }
  }
}

/// Every timer numbered like a strike deadline the recorder has seen armed, whatever process armed it,
/// in no order.
pub fn deadlines(recorder recorder: Recorder) -> List(Deadline) {
  let reply = process.new_subject()
  process.send(recorder.events, Collect(reply:))
  let assert Ok(found) = process.receive(reply, within: 60_000)
    as "the recorder answered"
  found
}

/// The deadlines of the creature process `creature`, earliest armed first.
pub fn of_creature(
  deadlines deadlines: List(Deadline),
  creature creature: Pid,
) -> List(Deadline) {
  list.filter(deadlines, fn(deadline) { deadline.creature == creature })
  |> list.sort(fn(first, second) {
    int.compare(first.armed_us, second.armed_us)
  })
}

fn record(
  events events: Subject(Event),
  deadlines deadlines: Dict(Reference, Deadline),
) -> Nil {
  case process.receive_forever(events) {
    Armed(reference:, deadline:) ->
      record(events:, deadlines: dict.insert(deadlines, reference, deadline))
    Elapsing(reference:, shell:, elapsed:) -> {
      let at_us = load_sample.microseconds()
      process.send(shell, elapsed)
      record(
        events:,
        deadlines: dict.upsert(deadlines, reference, fn(found) {
          case found {
            Some(Deadline(closure: Open, ..) as deadline) ->
              Deadline(..deadline, closure: Fired(at_us:))
            Some(deadline) -> deadline
            None -> panic as "a deadline fired that was never armed"
          }
        }),
      )
    }
    Closed(reference:, at_us:) ->
      record(
        events:,
        deadlines: dict.upsert(deadlines, reference, fn(found) {
          case found {
            Some(Deadline(closure: Open, ..) as deadline) ->
              Deadline(..deadline, closure: Cancelled(at_us:))
            Some(deadline) -> deadline
            None -> panic as "a deadline closed that was never armed"
          }
        }),
      )
    Collect(reply:) -> {
      process.send(reply, dict.values(deadlines))
      record(events:, deadlines:)
    }
  }
}
