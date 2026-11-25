//// How the fight load run's recorder tells how a strike deadline ended
//// (`genesis_prime/load_deadline`), through the scheduler the service shell calls, and
//// what the rounds count from it (`genesis_prime/load_round`).
//// - The recorder stamps a deadline's firing when its timer reaches the recorder, which is
////   before the creature's shell takes the `Elapsed`. A creature busy at the due time can
////   hold an answer ahead of that `Elapsed`; it takes the answer and cancels the deadline.
//// - The shell forgets a timer once it takes the firing (`step/timer.fired`), so a cancel
////   that reaches the recorder after the firing is one the shell made before it took the
////   firing: the answer closed the round, and the deadline did not.

import genesis_prime/load_deadline.{type Closure, Cancelled, Fired, Open}
import genesis_prime/load_round.{type Rounds, Answer, Closed, Rounds}
import genesis_prime/step.{TimerId}
import genesis_prime/world_map/creature
import gleam/dict
import gleam/erlang/process
import gleam/erlang/reference
import gleam/list
import open_wait
import owned_test

/// The timer a creature's shell arms for its strike deadline of generation 1.
const strike_deadline = TimerId(9)

/// What happens to a deadline the shell armed, in the order the recorder sees it.
type Order {
  CancelledBeforeDue
  FiredAndTaken
  FiredThenCancelled
}

/// Arms a strike deadline on a new recorder's scheduler as a creature's shell does (this
/// process is the shell), lets `order` happen to it, and gives the deadline as recorded.
fn recorded_after(order order: Order) -> load_deadline.Deadline {
  let recorder = load_deadline.start()
  let shell = process.new_subject()
  let after_ms = case order {
    CancelledBeforeDue -> 600_000
    FiredAndTaken | FiredThenCancelled -> 20
  }
  let cancel =
    load_deadline.scheduler(recorder:)(
      shell,
      strike_deadline,
      reference.new(),
      after_ms,
    )
  case order {
    CancelledBeforeDue -> cancel()
    FiredAndTaken -> {
      let _elapsed =
        open_wait.received(
          from: shell,
          what: "the recorder to send the shell its firing",
        )
      Nil
    }
    FiredThenCancelled -> {
      let _elapsed =
        open_wait.received(
          from: shell,
          what: "the recorder to send the shell its firing",
        )
      cancel()
    }
  }
  let assert [deadline] =
    load_deadline.of_creature(
      deadlines: load_deadline.deadlines(recorder:),
      creature: process.self(),
    )
    as "the recorder holds the one deadline armed"
  deadline
}

fn is_closed_by(closure closure: Closure) -> String {
  case closure {
    Open -> "open"
    Cancelled(..) -> "cancelled"
    Fired(..) -> "fired"
  }
}

pub fn a_deadline_the_shell_cancelled_after_the_recorder_stamped_its_firing_is_told_cancelled_and_its_answer_is_in_the_round_test() -> Nil {
  use <- owned_test.run(10_000)
  assert creature.is_strike_deadline(timer: strike_deadline)
    as "the timer is numbered like a creature's strike deadline"
  let none = Rounds(..counts_none(), answers: 1)
  let rows = [
    #(
      "cancelled before it fell due: the answer closed the round",
      CancelledBeforeDue,
      "cancelled",
      Rounds(..none, closed: Closed(..load_round.no_closures, answer: 1)),
    ),
    #(
      "fired and the shell took the firing, no cancel: the deadline closed the round without the answer",
      FiredAndTaken,
      "fired",
      Rounds(
        ..none,
        lost: 1,
        closed: Closed(..load_round.no_closures, deadline: 1),
      ),
    ),
    #(
      "fired at the recorder and then cancelled: the creature had the answer first and the cancel closed the round",
      FiredThenCancelled,
      "cancelled",
      Rounds(..none, closed: Closed(..load_round.no_closures, answer: 1)),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, order, closure, expected) = row
    let deadline = recorded_after(order:)
    assert is_closed_by(closure: deadline.closure) == closure as reason
    // An answer the walker took, sent and stamped at the arming, before the deadline fell
    // due and before any cancel.
    let answer =
      Answer(
        creature: process.self(),
        taken_us: deadline.armed_us,
        sent_us: deadline.armed_us,
        arrived_us: deadline.armed_us,
        delivered: True,
      )
    assert load_round.rounds_of(
        answers: [answer],
        strikers: dict.from_list([#(process.self(), 7)]),
        marks: [],
        deadlines: [deadline],
      )
      == expected
      as reason
  })
}

fn counts_none() -> Rounds {
  Rounds(
    answers: 0,
    undelivered: 0,
    unmatched: 0,
    lost: 0,
    late: 0,
    closed: load_round.no_closures,
  )
}
