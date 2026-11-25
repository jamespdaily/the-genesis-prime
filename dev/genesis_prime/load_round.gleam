//// The strike rounds of the fight load run, counted from what its walkers stamped
//// and what the recorder saw (`genesis_prime/load_deadline`). A stub: the counting
//// is not written yet.

import genesis_prime/load_deadline.{type Deadline}
import genesis_prime/load_sample
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/list

/// One strike a walker was told and answered, on the monotonic clock in
/// microseconds: when it took the strike, when it handed the answer over, and when
/// the creature had it (`delivered` is false when no creature was left to tell). The
/// creature is the process of the creature that struck.
pub type Answer {
  Answer(
    creature: Pid,
    taken_us: Int,
    sent_us: Int,
    arrived_us: Int,
    delivered: Bool,
  )
}

/// What a walker saw a creature do that closes a round without an answer.
pub type Sign {
  Released
  Died
  Interrupted
  Controlled
}

/// A sign of the creature that is unit `unit_id`, stamped when the walker took it.
pub type Mark {
  Mark(unit_id: Int, sign: Sign, at_us: Int)
}

/// How many rounds closed each way.
pub type Closed {
  Closed(
    answer: Int,
    deadline: Int,
    death: Int,
    control: Int,
    leash: Int,
    interrupt: Int,
    unexplained: Int,
    open: Int,
  )
}

/// What the strike rounds came to.
pub type Rounds {
  Rounds(
    answers: Int,
    undelivered: Int,
    unmatched: Int,
    lost: Int,
    late: Int,
    closed: Closed,
  )
}

/// No round closed any way.
pub const no_closures =
  Closed(
    answer: 0,
    deadline: 0,
    death: 0,
    control: 0,
    leash: 0,
    interrupt: 0,
    unexplained: 0,
    open: 0,
  )

/// Sends the answer with `send` and gives the microsecond it stamped for its
/// arrival and whether `send` told a creature.
pub fn stamped_send(send send: fn() -> Bool) -> #(Int, Bool) {
  let delivered = send()
  #(load_sample.microseconds(), delivered)
}

/// The rounds the answers belong to, counted by how they closed.
pub fn rounds_of(
  answers answers: List(Answer),
  strikers strikers: Dict(Pid, Int),
  marks marks: List(Mark),
  deadlines deadlines: List(Deadline),
) -> Rounds {
  let _ = #(strikers, marks, deadlines)
  Rounds(
    answers: list.length(answers),
    undelivered: 0,
    unmatched: 0,
    lost: 0,
    late: 0,
    closed: no_closures,
  )
}
