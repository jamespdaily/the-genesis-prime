//// The strike rounds of the fight load run (`genesis_prime/load_fight`), counted from
//// what its walkers stamped and saw and what the recorder saw of the creatures'
//// deadlines (`genesis_prime/load_deadline`). Pure: the run's tool gathers the stamps,
//// this module counts them, and a test plants them.
////
//// ```
//// answers (taken, sent, arrived) ─┐
//// strikers (creature process → unit) ─┼─▶ rounds_of ─▶ Rounds: lost, late, closures
//// signs seen by the walkers ───────┤
//// recorded deadlines ──────────────┘
//// ```
////
//// - An answer is matched to the latest round of the creature that struck, armed no
////   later than `match_slack_us` after the walker took the strike (the creature sends
////   the strike and arms the deadline in one step). A round is armed for each strike a
////   walker took, answered or not.
//// - **Lost:** sent before the round's deadline fell due and the round closed without it;
////   **late:** sent at or after it. A round the deadline closed (`Fired`: no cancel reached
////   the recorder) has no answer in it, whatever the walker stamped as the arrival: an
////   answer that reached the creature in time would have closed the round by cancelling its
////   deadline, so an answer sent in time to a round the deadline closed is one the creature
////   did not have, held wherever it was held. A round closed by a cancel has the answers
////   that reached the creature no later than the cancel, a cancel after the deadline fired at
////   the recorder included (`genesis_prime/load_deadline`); the arrival is stamped before
////   the send (`stamped_send`), so an answer that closed its round is in it.
//// - The rounds counted are those of the creatures that struck a walker, answered or
////   not (`strikers`): a creature none of whose strikes was answered still has its
////   rounds counted, and another service's timer with a deadline's number does not.
//// - A round closes by its answer, its deadline, or a cancel with a reason the
////   shell does not say; the reason is read from the signs the walkers saw of the
////   creature near the cancel: a death (`Died`), a crowd-control state of a walker's
////   own strike that broke the charge (`Controlled`), a charge broken with no such
////   state (`Interrupted`: a throw, or a state another unit put), the leash (`Released`
////   with neither). The rule's cancels are `creature_fight`'s `round_ended`, `killed`,
////   `held`, `charge_broken` and the answer's own.
////
//// Gaps: no scene of the run throws a creature, so `interrupt` counts only what a
//// walker did not mark as its own state; a cancel with no sign near it is `unexplained`.

import genesis_prime/client_connection.{
  type StaySent, SentByFoe, SentByKill, SentByMap, SentByPeer, SentByPlayer,
  SentByTarget,
}
import genesis_prime/game/strike_tell
import genesis_prime/load_deadline.{type Deadline}
import genesis_prime/load_sample
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result

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
  /// The creature released the walker: the leash, or a death.
  Released
  /// The creature died.
  Died
  /// The creature's charge was broken (the cast interrupted).
  Interrupted
  /// A crowd-control state of the walker's own strike broke the creature's charge: the
  /// answer to the strike named the cast it interrupted.
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

/// What the strike rounds came to: the answers, those told to no creature, those
/// matched to no round, those lost and late, and the rounds by how they closed.
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

/// How many rounds there were, closed any way or still open.
pub fn round_count(closed: Closed) -> Int {
  closed.answer
  + closed.deadline
  + closed.death
  + closed.control
  + closed.leash
  + closed.interrupt
  + closed.unexplained
  + closed.open
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

/// How far from a round's arming a walker's taking of its strike may be, in
/// microseconds, for the strike to be matched to the round.
const match_slack_us = 20_000

/// How long before a cancel and after it a walker's sign of the creature is taken to
/// be of that cancel, in microseconds: the creature cancels and then sends its news,
/// and a walker takes it when it next reads its mailbox. A creature's next round is
/// armed an attack interval (1,500 ms or more) after the last closed.
const sign_before_us = 50_000

const sign_after_us = 1_000_000

/// Stamps the microsecond just before `send` tells the creature the answer, and gives it
/// with whether `send` told a creature. The stamp is taken before the send, so a creature
/// that takes the answer and closes its round, however long the walker is paused after
/// the send, has an answer stamped no later than its closure.
pub fn stamped_send(send send: fn() -> Bool) -> #(Int, Bool) {
  let arrived_us = load_sample.microseconds()
  #(arrived_us, send())
}

/// The round each answer belongs to: the latest round of the creature that struck,
/// armed no later than `match_slack_us` after the walker took the strike, and not
/// fallen due more than `match_slack_us` before it.
fn round_of(
  answer answer: Answer,
  rounds rounds: List(Deadline),
) -> Result(Deadline, Nil) {
  list.filter(rounds, fn(round) {
    round.armed_us <= answer.taken_us + match_slack_us
  })
  |> list.last
  |> result.try(fn(round) {
    case answer.taken_us <= round.due_us + match_slack_us {
      True -> Ok(round)
      False -> Error(Nil)
    }
  })
}

/// Whether the creature had the answer when the round closed: any answer to a round
/// that is still open, none to a round its deadline closed, and one that reached the
/// creature no later than the cancel to a round a cancel closed.
fn in_round(answer answer: Answer, round round: Deadline) -> Bool {
  case round.closure {
    load_deadline.Open -> True
    load_deadline.Fired(..) -> False
    load_deadline.Cancelled(at_us:) -> answer.arrived_us <= at_us
  }
}

/// Whether a walker that stops hearing at `ends_ms` may make a strike at `at_ms`: only
/// with `strike_tell.deadline_ms` left to hear its answer, so every strike it makes is
/// owed one.
pub fn may_strike(at_ms at_ms: Int, ends_ms ends_ms: Int) -> Bool {
  at_ms <= ends_ms - strike_tell.deadline_ms
}

/// Whether what a walker was sent is a creature's answer to a strike of its own: the
/// `Struck` a creature tells the player who struck it.
pub fn is_answer_to_strike(sent sent: StaySent) -> Bool {
  case sent {
    SentByTarget(..) -> True
    SentByMap(..)
    | SentByPeer(..)
    | SentByFoe(..)
    | SentByPlayer(..)
    | SentByKill(..) -> False
  }
}

/// How a round closed.
type Reason {
  ByAnswer
  ByDeadline
  ByDeath
  ByControl
  ByInterrupt
  ByLeash
  Unexplained
  StillOpen
}

/// The rounds of the creatures in `strikers` (each creature's process with its unit) and
/// the answers to them, counted by `marks`, the signs the walkers saw.
pub fn rounds_of(
  answers answers: List(Answer),
  strikers strikers: Dict(Pid, Int),
  marks marks: List(Mark),
  deadlines deadlines: List(Deadline),
) -> Rounds {
  let by_creature = list.group(answers, fn(answer) { answer.creature })
  let matched =
    list.flat_map(dict.to_list(by_creature), fn(group) {
      let rounds = load_deadline.of_creature(deadlines:, creature: group.0)
      list.map(group.1, fn(answer) { #(answer, round_of(answer:, rounds:)) })
    })
  let #(undelivered, delivered) =
    list.partition(matched, fn(pair) { !{ pair.0 }.delivered })
  let #(unmatched, in_a_round) =
    list.partition(delivered, fn(pair) { result.is_error(pair.1) })
  let judged =
    list.filter_map(in_a_round, fn(pair) {
      result.map(pair.1, fn(round) { #(pair.0, round) })
    })
  let not_in_round =
    list.filter(judged, fn(pair) { !in_round(answer: pair.0, round: pair.1) })
  let lost =
    list.count(not_in_round, fn(pair) { { pair.0 }.sent_us < { pair.1 }.due_us })
  // The first answer to reach each round, by the creature and the round's arming.
  let first_arrival =
    list.fold(judged, dict.new(), fn(first, pair) {
      dict.upsert(first, #({ pair.1 }.creature, { pair.1 }.armed_us), fn(found) {
        case found {
          Some(earlier) -> int.min(earlier, { pair.0 }.arrived_us)
          None -> { pair.0 }.arrived_us
        }
      })
    })
  let closed =
    list.flat_map(dict.to_list(strikers), fn(striker) {
      load_deadline.of_creature(deadlines:, creature: striker.0)
      |> list.map(fn(round) {
        reason_of(
          round:,
          first_arrival: dict.get(first_arrival, #(
            round.creature,
            round.armed_us,
          )),
          signs: signs_near(marks:, unit_id: striker.1, round:),
        )
      })
    })
    |> list.fold(no_closures, counted)
  Rounds(
    answers: list.length(answers),
    undelivered: list.length(undelivered),
    unmatched: list.length(unmatched),
    lost:,
    late: list.length(not_in_round) - lost,
    closed:,
  )
}

/// The signs of the creature of `unit_id` taken near the round's cancel, none for a
/// round that was not cancelled.
fn signs_near(
  marks marks: List(Mark),
  unit_id unit_id: Int,
  round round: Deadline,
) -> List(Sign) {
  case round.closure {
    load_deadline.Cancelled(at_us:) ->
      list.filter_map(marks, fn(mark) {
        case
          mark.unit_id == unit_id
          && mark.at_us >= at_us - sign_before_us
          && mark.at_us <= at_us + sign_after_us
        {
          True -> Ok(mark.sign)
          False -> Error(Nil)
        }
      })
    load_deadline.Open | load_deadline.Fired(..) -> []
  }
}

/// How a round closed: its deadline firing; a cancel after an answer reached the
/// creature (the answer closed it); or, for a cancel without one, the strongest sign
/// seen: a death, then a state of a walker's, then a broken charge, then a release.
fn reason_of(
  round round: Deadline,
  first_arrival first_arrival: Result(Int, Nil),
  signs signs: List(Sign),
) -> Reason {
  case round.closure, first_arrival {
    load_deadline.Open, _ -> StillOpen
    load_deadline.Fired(..), _ -> ByDeadline
    load_deadline.Cancelled(at_us:), Ok(arrived_us) if arrived_us <= at_us ->
      ByAnswer
    load_deadline.Cancelled(..), _ ->
      case
        list.contains(signs, Died),
        list.contains(signs, Controlled),
        list.contains(signs, Interrupted),
        list.contains(signs, Released)
      {
        True, _, _, _ -> ByDeath
        False, True, _, _ -> ByControl
        False, False, True, _ -> ByInterrupt
        False, False, False, True -> ByLeash
        False, False, False, False -> Unexplained
      }
  }
}

fn counted(closed: Closed, reason: Reason) -> Closed {
  case reason {
    ByAnswer -> Closed(..closed, answer: closed.answer + 1)
    ByDeadline -> Closed(..closed, deadline: closed.deadline + 1)
    ByDeath -> Closed(..closed, death: closed.death + 1)
    ByControl -> Closed(..closed, control: closed.control + 1)
    ByInterrupt -> Closed(..closed, interrupt: closed.interrupt + 1)
    ByLeash -> Closed(..closed, leash: closed.leash + 1)
    Unexplained -> Closed(..closed, unexplained: closed.unexplained + 1)
    StillOpen -> Closed(..closed, open: closed.open + 1)
  }
}
