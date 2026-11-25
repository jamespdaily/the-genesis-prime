//// What the load runs count (`genesis_prime/load_round` for the fight run's strike
//// rounds, `genesis_prime/load_move_delay` for the movement run's delay), from planted
//// stamps: these counts decide whether the creature's deadline change and the map's
//// relay change merge, so each is checked here and not by reading a run.
//// - A strike's deadline is `strike_tell.deadline_ms` = 1,000 ms after its round is
////   armed (`creature_fight.StrikeDeadline`); the stamps below are microseconds on
////   one clock, the round armed at 0 and due at 1,000,000.
//// - **Lost** is an answer sent before the deadline fell due that the creature did
////   not have when the round closed; **late** is one sent at or after it (Design run A,
////   8.2).
//// - A round closes by an answer or by the leash, a death, a crowd-control state or an
////   interrupt, which cancel its timer (`creature_fight.round_ended`, `killed`,
////   `held`, `charge_broken`), or by its deadline.
//// - The move delay is from the mover's send to the viewer's receipt (Design run A,
////   8.1); a probe's step `k` is at z = the walkers' z + 0.01 `k`, and the walkers'
////   z is -560.18798828125 (World 3460, WorldLocation2 row 51596).

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/load_deadline.{type Closure, type Deadline, Deadline}
import genesis_prime/load_move_delay.{Probed}
import genesis_prime/load_round.{
  type Answer, type Closed, type Mark, type Rounds, Answer, Closed, Controlled,
  Died, Interrupted, Mark, Released, Rounds,
}
import genesis_prime/load_sample
import genesis_prime/message/float32
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import owned_test

/// The creature's process: one that only waits, so its pid names a creature.
fn creature() -> Pid {
  process.spawn(fn() { process.sleep_forever() })
}

/// A round of `creature` armed at 0 and due at 1,000,000, closed as `closure`.
fn round(creature creature: Pid, closure closure: Closure) -> Deadline {
  Deadline(creature:, armed_us: 0, due_us: 1_000_000, closure:)
}

/// A strike a walker took at 10,000 and answered, sent and arrived as given.
fn answer(
  creature creature: Pid,
  sent_us sent_us: Int,
  arrived_us arrived_us: Int,
) -> Answer {
  Answer(creature:, taken_us: 10_000, sent_us:, arrived_us:, delivered: True)
}

/// What one round of `creature`, unit 7, counts as, given the answers and the signs
/// the walkers saw.
fn counted(
  creature creature: Pid,
  answers answers: List(Answer),
  marks marks: List(Mark),
  closure closure: Closure,
) -> Rounds {
  load_round.rounds_of(
    answers:,
    strikers: dict.from_list([#(creature, 7)]),
    marks:,
    deadlines: [round(creature:, closure:)],
  )
}

pub fn an_answer_stamped_before_its_send_is_in_the_round_it_closed_whatever_the_walkers_pause_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature takes the answer, cancels the round and stamps the closure while the
  // send runs; a walker that is not scheduled again until after that stamps its
  // arrival after the closure if it stamps after the send. Each row is how long the
  // creature takes, in milliseconds.
  list.each([0, 2, 20], fn(creature_takes_ms) {
    let creature = creature()
    let closed = process.new_subject()
    let #(arrived_us, delivered) =
      load_round.stamped_send(send: fn() {
        process.sleep(creature_takes_ms)
        process.send(closed, load_sample.microseconds())
        True
      })
    let assert Ok(closed_us) = process.receive(closed, within: 0)
      as "the creature closed the round while the send ran"
    assert delivered
    assert arrived_us <= closed_us
      as "the arrival is stamped before the send, so it is never after the closure"
    let rounds =
      counted(
        creature:,
        answers: [
          Answer(
            creature:,
            taken_us: closed_us - 2_000_000,
            sent_us: closed_us - 1000,
            arrived_us:,
            delivered:,
          ),
        ],
        marks: [],
        closure: load_deadline.Cancelled(at_us: closed_us),
      )
    assert rounds.lost == 0 && rounds.late == 0
      as "an answer that closed its round is in it, not lost"
  })
}

pub fn a_round_is_lost_late_or_in_by_its_answers_times_against_the_armed_deadline_and_the_closure_test() -> Nil {
  use <- owned_test.run(5000)
  let creature = creature()
  let one = fn(closed: Closed) {
    Rounds(answers: 0, undelivered: 0, unmatched: 0, lost: 0, late: 0, closed:)
  }
  let answered = fn(rounds: Rounds) { Rounds(..rounds, answers: 1) }
  let rows = [
    #(
      "sent before the deadline and in the round: closed by the answer",
      [answer(creature:, sent_us: 400_000, arrived_us: 410_000)],
      load_deadline.Cancelled(at_us: 420_000),
      answered(one(Closed(..load_round.no_closures, answer: 1))),
    ),
    #(
      "sent before the deadline and not in the round: the creature had it after the deadline closed the round",
      [answer(creature:, sent_us: 900_000, arrived_us: 1_100_000)],
      load_deadline.Fired(at_us: 1_000_000),
      Rounds(
        ..answered(one(Closed(..load_round.no_closures, deadline: 1))),
        lost: 1,
      ),
    ),
    #(
      "sent after the deadline: late, not lost",
      [answer(creature:, sent_us: 1_100_000, arrived_us: 1_100_000)],
      load_deadline.Fired(at_us: 1_000_000),
      Rounds(
        ..answered(one(Closed(..load_round.no_closures, deadline: 1))),
        late: 1,
      ),
    ),
    #(
      "no answer and the deadline closed the round",
      [],
      load_deadline.Fired(at_us: 1_000_000),
      one(Closed(..load_round.no_closures, deadline: 1)),
    ),
    #(
      "no answer and the round was cancelled with no sign of why",
      [],
      load_deadline.Cancelled(at_us: 300_000),
      one(Closed(..load_round.no_closures, unexplained: 1)),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, answers, closure, expected) = row
    assert counted(creature:, answers:, marks: [], closure:) == expected
      as reason
  })
}

pub fn a_creature_that_struck_and_got_no_answer_counts_its_rounds_test() -> Nil {
  use <- owned_test.run(5000)
  let striker = creature()
  let map = creature()
  let counted_with = fn(process: Pid, marks: List(Mark), closure: Closure) -> Closed {
    load_round.rounds_of(
      answers: [],
      strikers: dict.from_list([#(striker, 7)]),
      marks:,
      deadlines: [round(creature: process, closure:)],
    ).closed
  }
  let rows = [
    #(
      "every strike unanswered and the deadline closed the round",
      counted_with(striker, [], load_deadline.Fired(at_us: 1_000_000)),
      Closed(..load_round.no_closures, deadline: 1),
    ),
    #(
      "every strike unanswered and the creature died",
      counted_with(
        striker,
        [Mark(unit_id: 7, sign: Died, at_us: 301_000)],
        load_deadline.Cancelled(at_us: 300_000),
      ),
      Closed(..load_round.no_closures, death: 1),
    ),
    #(
      "a round of a process that struck no walker, such as the map's restart timer of the spawn numbered 9, is no creature's",
      counted_with(map, [], load_deadline.Fired(at_us: 1_000_000)),
      load_round.no_closures,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, closed, expected) = row
    assert closed == expected as reason
  })
}

pub fn closures_are_counted_by_their_reason_test() -> Nil {
  use <- owned_test.run(5000)
  let creature = creature()
  let sign = fn(sign, at_us) { Mark(unit_id: 7, sign:, at_us:) }
  let cancelled = load_deadline.Cancelled(at_us: 300_000)
  let rows = [
    #(
      "the deadline",
      [],
      load_deadline.Fired(at_us: 1_000_000),
      [],
      Closed(..load_round.no_closures, deadline: 1),
    ),
    #(
      "an answer",
      [answer(creature:, sent_us: 100_000, arrived_us: 200_000)],
      cancelled,
      [],
      Closed(..load_round.no_closures, answer: 1),
    ),
    #(
      "a death, which also releases",
      [],
      cancelled,
      [sign(Released, 301_000), sign(Died, 300_500)],
      Closed(..load_round.no_closures, death: 1),
    ),
    #(
      "a crowd-control state, which also breaks the charge",
      [],
      cancelled,
      [sign(Interrupted, 301_500), sign(Controlled, 301_000)],
      Closed(..load_round.no_closures, control: 1),
    ),
    #(
      "the leash: released and not dead",
      [],
      cancelled,
      [sign(Released, 301_000)],
      Closed(..load_round.no_closures, leash: 1),
    ),
    #(
      "an interrupt: the charge broken with no state of a walker's",
      [],
      cancelled,
      [sign(Interrupted, 301_000)],
      Closed(..load_round.no_closures, interrupt: 1),
    ),
    #(
      "a sign of another round, seconds after",
      [],
      cancelled,
      [sign(Died, 9_000_000)],
      Closed(..load_round.no_closures, unexplained: 1),
    ),
    #(
      "a round still open",
      [],
      load_deadline.Open,
      [],
      Closed(..load_round.no_closures, open: 1),
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, answers, closure, marks, expected) = row
    assert counted(creature:, answers:, marks:, closure:).closed == expected
      as reason
  })
}

/// The 0x0638 of unit `unit_id` with one position at the walkers' z plus `hundredths`
/// hundredths.
fn moved(unit_id unit_id: Int, hundredths hundredths: Int) -> Frame {
  let assert Ok(body) =
    unit_movement.encode(
      UnitMovement(
        unit_id:,
        server_time: 0,
        reset_movement: 0,
        kept: 0,
        commands: [
          relayed_movement.Position(UnitPositionCommand(
            x: float32.to_bits(29.0),
            y: float32.to_bits(-853.0),
            z: float32.to_bits(
              -560.18798828125 +. 0.01 *. int.to_float(hundredths),
            ),
            blends: 0,
          )),
        ],
      ),
    )
    as "a 0x0638 encodes"
  Frame(message_id: 0x0638, body:)
}

/// The unit and step of each frame that is a probe's move, with the stamp it was taken at.
fn read(frames: List(#(Frame, Int))) -> List(#(Int, Int, Int)) {
  list.filter_map(frames, fn(stamped) {
    case load_move_delay.step_of(stamped.0) {
      Ok(#(unit_id, step)) -> Ok(#(unit_id, step, stamped.1))
      Error(Nil) -> Error(Nil)
    }
  })
}

pub fn the_move_delay_is_taken_per_viewer_from_the_movers_send_to_the_viewers_take_test() -> Nil {
  use <- owned_test.run(5000)
  let walkers_move = moved(unit_id: 30, hundredths: 0)
  let not_a_move = Frame(message_id: 0x0637, body: <<>>)
  // Probe 1 (unit 10) and probe 2 (unit 20) each send steps 1 to 3, stamped as below.
  let sent_by_one = dict.from_list([#(1, 1000), #(2, 126_000), #(3, 251_000)])
  let sent_by_two = dict.from_list([#(1, 2000), #(2, 127_000), #(3, 252_000)])
  let seen_by_one =
    read([
      #(moved(unit_id: 20, hundredths: 1), 5000),
      #(walkers_move, 6000),
      #(not_a_move, 7000),
      #(moved(unit_id: 20, hundredths: 2), 132_000),
    ])
  let seen_by_two =
    read([
      #(moved(unit_id: 10, hundredths: 1), 2000),
      #(moved(unit_id: 10, hundredths: 2), 128_000),
      #(moved(unit_id: 10, hundredths: 3), 255_000),
    ])
  let delays =
    load_move_delay.delays(probed: [
      Probed(unit_id: 10, sent_us: sent_by_one, seen: seen_by_one),
      Probed(unit_id: 20, sent_us: sent_by_two, seen: seen_by_two),
    ])
  assert list.sort(delays.microseconds, int.compare)
    == [1000, 2000, 3000, 4000, 5000]
    as "probe 2 read probe 1's steps 1 to 3 after 1,000, 2,000 and 4,000; probe 1 read probe 2's steps 1 and 2 after 3,000 and 5,000; the walker's move and the other message are no step"
  assert delays.expected == 6
    as "each of two probes sent 3 moves to the other: probe 1 never read probe 2's step 3"
  assert load_move_delay.summary(delays:)
    == load_move_delay.Summary(
      moves: 5,
      mean_us: 3000,
      p99_us: 5000,
      longest_us: 5000,
    )
    as "the mean of 15,000 over 5; the nearest-rank 99th of five values is the fifth"
}
