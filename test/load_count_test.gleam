//// What the load runs count (`genesis_prime/load_round` for the fight run's strike
//// rounds, `genesis_prime/load_move_delay` for the movement run's delay,
//// `genesis_prime/load_sight` for the players and casts a client read,
//// `genesis_prime/load_queue` for the map's queue), from planted
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
//// - A respawn is a unit's removal, then its next creation, as the walker was sent them:
////   the creature's own news (`SentByPeer`: `Removed`, `CreatureAppeared`) or the map's
////   notice (`SentByMap`: `UnitUnseen`, `Gone`, `ObjectsUnseen`, `ObjectsSeen`); its gap is
////   the time between the two (`load_respawn`).
//// - The move delay is from the mover's send to the viewer's receipt (Design run A,
////   8.1); a probe's step `k` is at z = the walkers' z + 0.01 `k`, and the walkers'
////   z is -560.18798828125 (World 3460, WorldLocation2 row 51596).
//// - A client is shown a player by a 0x262 of that player's unit and no longer by the
////   unit's 0x355 (`opcode.0x262`, `opcode.0x355`); a frame for a unit after its 0x355 and
////   before its next 0x262 breaks that order (`legal_order_support.check_frames`).
//// - A cast is read as a 0x7ff, a 0x7f4 and a 0x7fe (`opcode.0x7ff`); a cast is owed a
////   probe once it finished a settle time before the probes stopped reading. A press of the
////   casting scene's ability writes a viewer the frames the scene owes per press, which the
////   client's tables give (Spell4 32893 and the Proxy rows of its Spell4Effects).

import character_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection.{
  type StaySent, SentByFoe, SentByMap, SentByPeer, SentByTarget,
}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news.{PeerNews, Removed}
import genesis_prime/load_deadline.{type Closure, type Deadline, Deadline}
import genesis_prime/load_judged.{type Judged, Judged, Respawns}
import genesis_prime/load_move_delay.{Probed}
import genesis_prime/load_player
import genesis_prime/load_queue.{Probe, Second}
import genesis_prime/load_respawn.{type Gaps, Gaps}
import genesis_prime/load_round.{
  type Answer, type Closed, type Mark, type Rounds, Answer, Closed, Controlled,
  Died, Interrupted, Mark, Released, Rounds,
}
import genesis_prime/load_sample
import genesis_prime/load_sight
import genesis_prime/message/float32
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_death_state.{UnitDeathState}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_health.{UnitHealth}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/shared/spell_plan
import genesis_prime/shared/telegraph_entries
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/generation
import genesis_prime/world_map/map.{Gone, ObjectsSeen, ObjectsUnseen, UnitUnseen}
import genesis_prime/world_map/player_unit
import gleam/bool
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/option
import gleam/set
import legal_order_support
import owned_test
import place_support
import spawn_support
import unit_support

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

/// Returns when the clock has run `microseconds` on.
fn clock_runs_on(microseconds microseconds: Int) -> Nil {
  let until_us = load_sample.microseconds() + microseconds
  clock_reaches(until_us:)
}

fn clock_reaches(until_us until_us: Int) -> Nil {
  use <- bool.guard(when: load_sample.microseconds() >= until_us, return: Nil)
  clock_reaches(until_us:)
}

pub fn an_answer_stamped_before_its_send_is_in_the_round_it_closed_whatever_the_walkers_pause_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature takes the answer, cancels the round and stamps the closure while the
  // send runs; a walker that is not scheduled again until after that stamps its
  // arrival after the closure if it stamps after the send. Each row is how long the
  // walker is paused after the send, in microseconds.
  list.each([1, 2000, 20_000], fn(pause_us) {
    let creature = creature()
    let closed = process.new_subject()
    let #(arrived_us, delivered) =
      load_round.stamped_send(send: fn() {
        clock_runs_on(microseconds: 1)
        process.send(closed, load_sample.microseconds())
        clock_runs_on(microseconds: pause_us)
        True
      })
    let assert Ok(closed_us) = process.receive(closed, within: 0)
      as "the creature closed the round while the send ran"
    assert delivered
    assert arrived_us <= closed_us
      as "the arrival is stamped before the send, so it is never after the closure"
    let rounds =
      load_round.rounds_of(
        answers: [
          Answer(
            creature:,
            taken_us: closed_us - 400_000,
            sent_us: closed_us - 1000,
            arrived_us:,
            delivered:,
          ),
        ],
        strikers: dict.from_list([#(creature, 7)]),
        marks: [],
        deadlines: [
          Deadline(
            creature:,
            armed_us: closed_us - 500_000,
            due_us: closed_us + 500_000,
            closure: load_deadline.Cancelled(at_us: closed_us),
          ),
        ],
      )
    assert rounds.unmatched == 0 && rounds.lost == 0 && rounds.late == 0
      as "an answer that closed its round is in it, not lost"
    assert rounds.closed == Closed(..load_round.no_closures, answer: 1)
      as "and the round is closed by the answer"
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
      "sent before the deadline, the deadline fired at the recorder and then the creature cancelled the round: it had the answer first, so the round is closed by the answer",
      [answer(creature:, sent_us: 900_000, arrived_us: 950_000)],
      load_deadline.Cancelled(at_us: 1_005_000),
      answered(one(Closed(..load_round.no_closures, answer: 1))),
    ),
    #(
      "sent before the deadline, the deadline fired at the recorder and then the creature cancelled the round, the answer reaching it after the cancel: lost",
      [answer(creature:, sent_us: 900_000, arrived_us: 1_100_000)],
      load_deadline.Cancelled(at_us: 1_005_000),
      Rounds(
        ..answered(one(Closed(..load_round.no_closures, unexplained: 1))),
        lost: 1,
      ),
    ),
    #(
      "sent before the deadline and stamped arrived before it closed the round, the map having held it after the stamp: the deadline closed the round without the answer, so it is lost whatever the walker stamped",
      [answer(creature:, sent_us: 900_000, arrived_us: 950_000)],
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

/// The creature's own news of unit `unit_id`: its creation as a Beast's process sends it.
fn created_by_creature(unit_id unit_id: Int) -> StaySent {
  SentByPeer(
    connection_support.beast_news(
      unit_id:,
      yaw: 0.0,
      casts: [],
      as_spawn: fn(beast) { beast },
    ),
  )
}

/// The creature's own news of the removal of unit `unit_id`.
fn removed_by_creature(unit_id unit_id: Int) -> StaySent {
  SentByPeer(PeerNews(unit_id:, news: Removed))
}

/// The map's notice that creates the static object `unit_id` (`ObjectsSeen`).
fn created_by_map(unit_id unit_id: Int) -> StaySent {
  let object =
    spawn_support.holoring(
      number: unit_id,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 0.0,
        y: 0.0,
        z: 0.0,
      ),
    )
  SentByMap(ObjectsSeen(units: [spawn_support.seen(object:, unit_id:)]))
}

/// The gaps, in microseconds, of the respawns a walker counts from these messages, each
/// sent at the time given.
fn gaps_of(sent sent: List(#(StaySent, Int))) -> List(Int) {
  list.fold(sent, load_respawn.none(), fn(gaps, one) {
    load_respawn.told(gaps:, sent: one.0, at_us: one.1)
  }).gaps_us
}

/// Each row is what a walker was sent (a message and when) and the gaps it counts; the
/// forms are the ones the creature's news and the map's notices tell a removal and a
/// creation in (`unit_news.News`, `map.Notice`).
pub fn a_respawn_is_read_from_every_form_that_tells_a_removal_then_a_creation_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "a removal then a creation, both the creature's own news: one gap",
      [
        #(removed_by_creature(unit_id: 7), 1000),
        #(created_by_creature(unit_id: 7), 1600),
      ],
      [600],
    ),
    #(
      "a creation with no removal before it: none",
      [#(created_by_creature(unit_id: 7), 1600)],
      [],
    ),
    #(
      "a removal by the map (Gone), then a creation by the map (ObjectsSeen): one gap",
      [
        #(SentByMap(Gone(unit_id: 7)), 1000),
        #(created_by_map(unit_id: 7), 1250),
      ],
      [250],
    ),
    #(
      "a removal by the map (ObjectsUnseen of two units), then the map's creation of one: one gap",
      [
        #(SentByMap(ObjectsUnseen(unit_ids: [7, 8])), 1000),
        #(created_by_map(unit_id: 8), 1300),
      ],
      [300],
    ),
    #(
      "a removal by the map (UnitUnseen), then the creature's creation: one gap",
      [
        #(
          SentByMap(UnitUnseen(unit_id: 7, generation: generation.first())),
          1000,
        ),
        #(created_by_creature(unit_id: 7), 1100),
      ],
      [100],
    ),
    #(
      "a removal by the creature, then the map's creation: one gap",
      [
        #(removed_by_creature(unit_id: 7), 1000),
        #(created_by_map(unit_id: 7), 1900),
      ],
      [900],
    ),
    #(
      "a removal of another unit before the creation: none",
      [
        #(removed_by_creature(unit_id: 8), 1000),
        #(created_by_creature(unit_id: 7), 1600),
      ],
      [],
    ),
    #(
      "a second creation after one removal: only the first is a respawn",
      [
        #(removed_by_creature(unit_id: 7), 1000),
        #(created_by_creature(unit_id: 7), 1600),
        #(created_by_creature(unit_id: 7), 2600),
      ],
      [600],
    ),
    #(
      "two respawns of one unit: two gaps",
      [
        #(removed_by_creature(unit_id: 7), 1000),
        #(created_by_creature(unit_id: 7), 1600),
        #(SentByMap(Gone(unit_id: 7)), 3000),
        #(created_by_map(unit_id: 7), 3200),
      ],
      [200, 600],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, sent, expected) = row
    assert list.sort(gaps_of(sent:), int.compare) == expected as reason
  })
}

/// A walker that saw units die at the given times, and respawn after the given gaps.
fn saw(deaths deaths: List(Int), gaps gaps: List(Int)) -> Gaps {
  Gaps(removed_at_us: dict.new(), gaps_us: gaps, deaths_at_us: deaths)
}

/// Each row is what the walkers counted, when they stopped (10,000,000), the respawns seen
/// and the fewest owed, and whether the run fails: it fails with no respawn, or with fewer
/// than the creatures killed, not counting a death within the settle time (3,000,000) of
/// the end, which is not owed one yet.
pub fn the_respawn_gate_fails_for_no_respawn_or_fewer_than_the_creatures_killed_test() -> Nil {
  use <- owned_test.run(5000)
  let judged = fn(all: List(Gaps)) -> Judged {
    Judged(
      event: Respawns,
      count: load_respawn.seen(all:),
      minimum: load_respawn.needed(
        all:,
        ended_us: 10_000_000,
        settle_us: 3_000_000,
      ),
    )
  }
  let rows = [
    #(
      "no creature died and none respawned: the run saw no respawn",
      [saw(deaths: [], gaps: [])],
      Judged(event: Respawns, count: 0, minimum: 1),
      True,
    ),
    #(
      "creatures died and none respawned: the run saw no respawn",
      [saw(deaths: [1_000_000], gaps: [])],
      Judged(event: Respawns, count: 0, minimum: 1),
      True,
    ),
    #(
      "three deaths long before the end, two respawns: fewer than killed",
      [saw(deaths: [1_000_000, 2_000_000, 3_000_000], gaps: [10, 20])],
      Judged(event: Respawns, count: 2, minimum: 3),
      True,
    ),
    #(
      "a death within the settle time of the end is not owed a respawn",
      [saw(deaths: [1_000_000, 8_000_000], gaps: [10])],
      Judged(event: Respawns, count: 1, minimum: 1),
      False,
    ),
    #(
      "the deaths and respawns of two walkers are summed",
      [
        saw(deaths: [1_000_000], gaps: [10]),
        saw(deaths: [1_000_000, 2_000_000], gaps: [10]),
      ],
      Judged(event: Respawns, count: 2, minimum: 3),
      True,
    ),
    #(
      "as many respawns as deaths owed one",
      [saw(deaths: [1_000_000, 2_000_000], gaps: [10, 20])],
      Judged(event: Respawns, count: 2, minimum: 2),
      False,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, all, expected, fails) = row
    assert judged(all) == expected as reason
    assert case load_judged.judge(judged: [judged(all)], conditions: []) {
        load_judged.Fails(..) -> True
        load_judged.Passes(..) -> False
      }
      == fails
      as reason
  })
}

pub fn a_death_the_creature_tells_is_stamped_for_the_gate_test() -> Nil {
  use <- owned_test.run(5000)
  let gaps =
    load_respawn.told(
      gaps: load_respawn.none(),
      sent: SentByPeer(PeerNews(unit_id: 7, news: unit_news.Died)),
      at_us: 4000,
    )
  assert gaps.deaths_at_us == [4000]
    as "a creature's Died news is a death, stamped when the walker was sent it"
}

pub fn a_round_the_deadline_closed_has_lost_every_answer_sent_before_it_fell_due_whatever_the_walker_stamped_test() -> Nil {
  use <- owned_test.run(5000)
  // Three creatures, each with one round armed at 0 and due at 1,000,000.
  let held_by_the_map = creature()
  let sent_after = creature()
  let cancelled = creature()
  let rounds =
    load_round.rounds_of(
      answers: [
        // Sent before the deadline fell due and stamped arrived before the round's
        // closure, as a walker stamps it just before a send to the map; the creature
        // has it after the deadline closed the round.
        answer(creature: held_by_the_map, sent_us: 900_000, arrived_us: 950_000),
        answer(creature: sent_after, sent_us: 1_100_000, arrived_us: 1_100_000),
        answer(creature: cancelled, sent_us: 400_000, arrived_us: 410_000),
      ],
      strikers: dict.from_list([
        #(held_by_the_map, 7),
        #(sent_after, 8),
        #(cancelled, 9),
      ]),
      marks: [],
      deadlines: [
        round(
          creature: held_by_the_map,
          closure: load_deadline.Fired(at_us: 1_000_000),
        ),
        round(
          creature: sent_after,
          closure: load_deadline.Fired(at_us: 1_000_000),
        ),
        round(
          creature: cancelled,
          closure: load_deadline.Cancelled(at_us: 420_000),
        ),
      ],
    )
  assert rounds.lost == 1
    as "the answer sent before the deadline fell due is lost, whatever it was stamped"
  assert rounds.late == 1 as "the answer sent after it is late"
  assert rounds.closed
    == Closed(..load_round.no_closures, deadline: 2, answer: 1)
    as "the cancelled round is closed by its answer, which it has"
}

pub fn a_walker_strikes_only_while_a_deadline_is_left_and_each_strike_it_makes_is_owed_an_answer_test() -> Nil {
  use <- owned_test.run(5000)
  // A walker may strike while it still has `strike_tell.deadline_ms` = 1,000 ms to hear
  // the answer, so every strike it makes is owed one: the rows are the strike's time and
  // the time the walker stops hearing, in milliseconds.
  let rows = [
    #("a strike at the start of a long walk", 0, 30_000, True),
    #(
      "a strike exactly a deadline before the walker stops",
      29_000,
      30_000,
      True,
    ),
    #("a strike a millisecond later is not made", 29_001, 30_000, False),
    #("a strike at the end is not made", 30_000, 30_000, False),
  ]
  list.each(rows, fn(row) {
    let #(reason, at_ms, ends_ms, may) = row
    assert load_round.may_strike(at_ms:, ends_ms:) == may as reason
  })
  let answered =
    strike_tell.Answered(
      key: strike_tell.Key(
        cast_id: 1,
        occasion: strike_tell.AtGo(phase: 0),
        unit_id: 7,
      ),
      outcome: strike_tell.Refused(why: strike_tell.Dead),
    )
  assert load_round.is_answer_to_strike(sent: SentByTarget(answered:))
    as "a creature's answer to a walker's strike is heard"
  assert !load_round.is_answer_to_strike(
    sent: SentByFoe(fight: strike_tell.Released(unit_id: 7)),
  )
    as "a creature's release of the walker is not"
}

pub fn the_maps_queue_is_read_by_the_second_and_a_mailbox_by_the_kind_of_its_messages_test() -> Nil {
  use <- owned_test.run(5000)
  // A queue of 3 sampled each 10 ms for 30 s, and a spike at 5.2 s: 7,750 at 5,200 ms
  // (the longest queue of the 200-walker fight run) and 4,000 at 5,210 ms, then 900 at
  // 6,000 ms.
  let series =
    list.repeat(Nil, 3000)
    |> list.index_map(fn(_, index) {
      let at_ms = index * 10
      case at_ms {
        5200 -> #(at_ms, 7750)
        5210 -> #(at_ms, 4000)
        6000 -> #(at_ms, 900)
        _ -> #(at_ms, 3)
      }
    })
  let seconds = load_queue.by_second(series:)
  assert list.length(seconds) == 30 as "a second for each of the 30 s sampled"
  assert list.take(seconds, 7)
    == [
      Second(second: 0, longest: 3),
      Second(second: 1, longest: 3),
      Second(second: 2, longest: 3),
      Second(second: 3, longest: 3),
      Second(second: 4, longest: 3),
      Second(second: 5, longest: 7750),
      Second(second: 6, longest: 900),
    ]
    as "each second holds the longest queue of its samples, whichever came first"
  assert load_queue.peak(series:) == Ok(Second(second: 5, longest: 7750))
    as "the peak is the second that holds the spike, with its longest queue"
  assert load_queue.peak(series: []) == Error(Nil)
    as "a run that took no sample has no peak"
  let names = [
    "Moved", "Snapshot", "Snapshot", "Broadcast", "Snapshot", "Moved",
    "Snapshot", "Broadcast", "Snapshot", "Moved",
  ]
  assert load_queue.kinds(names:)
    == [#("Snapshot", 5), #("Moved", 3), #("Broadcast", 2)]
    as "ten messages of three kinds, counted by kind, the largest first"
  assert load_queue.kinds(names: ["Moved", "Asked", "Moved", "Asked", "Told"])
    == [#("Asked", 2), #("Moved", 2), #("Told", 1)]
    as "kinds of the same count come in alphabetical order"
}

/// The 0x262 of the player `unit_id`.
fn player_created(unit_id unit_id: Int) -> Frame {
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 1.0,
      y: 2.0,
      z: 3.0,
    )
  let record =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: character_support.character(number: unit_id),
        place:,
        unit_id:,
        body: [],
      ),
      realm_id: 1,
    )
  let assert Ok(body) = unit_create_player.encode(record) as "0x262 encodes"
  Frame(message_id: 0x0262, body:)
}

/// The 0x262 of the Battle Beast as the creature `unit_id`.
fn creature_created(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_create_creature.encode(creature_unit.create(
      spawn: legal_order_support.the_beast(),
      unit_id:,
      health: 52,
      interrupt_armor: option.None,
      server_time_estimate_start: 0,
    ))
    as "a creature's 0x262 encodes"
  Frame(message_id: 0x0262, body:)
}

/// The 0x355 of `unit_id`.
fn removed(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_destroyed.encode(UnitDestroyed(unit_id:, chest_world_object_delay: 0))
    as "a 0x355 encodes"
  Frame(message_id: 0x0355, body:)
}

/// The 0x937 of `unit_id`.
fn health_of(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_health.encode(UnitHealth(unit_id:, health: 50, dead: 0))
    as "a 0x937 encodes"
  Frame(message_id: 0x0937, body:)
}

/// The 0x88c of `unit_id`.
fn death_of(unit_id unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_death_state.encode(UnitDeathState(
      unit_id:,
      dead: 1,
      unread_3: 0,
      health: 0,
    ))
    as "a 0x88c encodes"
  Frame(message_id: 0x088C, body:)
}

fn a_place() -> start_place.Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x: 1.0, y: 2.0, z: 3.0)
}

/// The 0x7ff of the cast `cast_id` of the unit `caster`.
fn cast_started(cast_id cast_id: Int, caster caster: Int) -> Frame {
  cast_frame.started_frame(start: cast_frame.creature_started(
    cast_id:,
    spell4_id: 32_893,
    caster_unit_id: caster,
    target_unit_id: 0,
    place: a_place(),
    opening: telegraph_entries.none,
  ))
}

/// The 0x7f4 of the cast `cast_id`.
fn cast_went(cast_id cast_id: Int) -> Frame {
  cast_frame.went_frame(
    go: cast_frame.creature_went(
      cast_id:,
      phase: 0,
      place: a_place(),
      struck: [],
    ),
  )
}

/// The 0x7fe of the cast `cast_id`.
fn cast_finished(cast_id cast_id: Int) -> Frame {
  cast_frame.finished_frame(cast_id:)
}

/// The sight of a client whose own unit is 1, after it read the frames, the one at
/// index `n` at `n` thousand microseconds.
fn sight_of(frames frames: List(Frame)) -> load_sight.Sight {
  list.index_fold(
    frames,
    load_sight.new(own_unit_id: 1),
    fn(sight, frame, index) {
      load_sight.read(sight:, frame:, at_us: index * 1000)
    },
  )
}

pub fn a_walker_that_read_every_other_players_0x262_once_counts_its_pairs_and_one_that_missed_one_counts_fewer_test() -> Nil {
  use <- owned_test.run(5000)
  // Five players, the walker's own unit 1: the walker is owed one 0x262 for each of the
  // four others (the client creates a unit on a 0x262 and drops it on its 0x355,
  // opcode.0x262).
  let rows = [
    #(
      "every other player's create once",
      [2, 3, 4, 5] |> list.map(player_created),
      4,
    ),
    #("one create missed", [2, 3, 4] |> list.map(player_created), 3),
    #(
      "a create repeated while the unit is shown counts once",
      [2, 3, 3, 4, 5, 2] |> list.map(player_created),
      4,
    ),
    #(
      "a create after the unit's removal counts again",
      list.flatten([
        [2, 3, 4, 5] |> list.map(player_created),
        [removed(unit_id: 3), player_created(unit_id: 3)],
      ]),
      5,
    ),
    #(
      "a removal of a unit never created counts none",
      [removed(unit_id: 9), player_created(unit_id: 2)],
      1,
    ),
    #(
      "the walker's own create is no pair",
      [1, 2, 3, 4, 5] |> list.map(player_created),
      4,
    ),
    #(
      "a creature's create is no player",
      [creature_created(unit_id: 40), player_created(unit_id: 2)],
      1,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, frames, pairs) = row
    assert load_sight.players_shown(sights: [sight_of(frames:)]) == pairs
      as reason
  })
  assert load_sight.players_shown(sights: [
      sight_of(frames: [2, 3, 4, 5] |> list.map(player_created)),
      sight_of(frames: [2, 3, 4] |> list.map(player_created)),
    ])
    == 7
    as "the pairs of the clients are added: four and three"
}

pub fn a_probe_that_reads_a_frame_of_a_unit_after_its_0x355_counts_a_violation_until_the_unit_is_created_again_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "0x262, 0x638, 0x355, 0x638, 0x262, 0x638 of unit 7: the 0x638 after the 0x355 only",
      [
        player_created(unit_id: 7),
        moved(unit_id: 7, hundredths: 1),
        removed(unit_id: 7),
        moved(unit_id: 7, hundredths: 2),
        player_created(unit_id: 7),
        moved(unit_id: 7, hundredths: 3),
      ],
      1,
    ),
    #(
      "two frames after the removal are two",
      [
        player_created(unit_id: 7),
        removed(unit_id: 7),
        moved(unit_id: 7, hundredths: 1),
        moved(unit_id: 7, hundredths: 2),
      ],
      2,
    ),
    #(
      "another unit's frame after the removal is none",
      [
        player_created(unit_id: 7),
        player_created(unit_id: 8),
        removed(unit_id: 7),
        moved(unit_id: 8, hundredths: 1),
      ],
      0,
    ),
    #(
      "a frame of a unit never created is the client's logged drop, no violation",
      [moved(unit_id: 9, hundredths: 1)],
      0,
    ),
    #(
      "a 0x937 and a 0x88c after the removal are two",
      [
        player_created(unit_id: 7),
        removed(unit_id: 7),
        health_of(unit_id: 7),
        death_of(unit_id: 7),
      ],
      2,
    ),
    #(
      "a 0x937 of a unit still shown is none",
      [
        player_created(unit_id: 7),
        player_created(unit_id: 8),
        removed(unit_id: 7),
        health_of(unit_id: 8),
      ],
      0,
    ),
    #(
      "a removed caster's go and end by cast id, and a new cast of it, are three",
      [
        player_created(unit_id: 7),
        cast_started(cast_id: 1, caster: 7),
        removed(unit_id: 7),
        cast_went(cast_id: 1),
        cast_finished(cast_id: 1),
        cast_started(cast_id: 2, caster: 7),
      ],
      3,
    ),
    #(
      "the end of a cast of a unit still shown is none",
      [
        player_created(unit_id: 7),
        player_created(unit_id: 8),
        cast_started(cast_id: 1, caster: 7),
        removed(unit_id: 8),
        cast_finished(cast_id: 1),
      ],
      0,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, frames, violations) = row
    assert load_sight.frames_after_removal(sights: [sight_of(frames:)])
      == violations
      as reason
  })
}

pub fn a_client_counts_each_removal_of_a_player_it_was_shown_and_no_other_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #(
      "two players shown, both removed",
      [2, 3] |> list.map(player_created),
      [2, 3],
      2,
    ),
    #(
      "a removal of a unit never created is none",
      [player_created(unit_id: 2)],
      [9],
      0,
    ),
    #(
      "a second removal of a player already removed is none",
      [player_created(unit_id: 2)],
      [2, 2],
      1,
    ),
    #("a creature's removal is none", [creature_created(unit_id: 40)], [40], 0),
  ]
  list.each(rows, fn(row) {
    let #(reason, created, gone, removals) = row
    let frames = list.append(created, list.map(gone, removed))
    assert load_sight.removals_read(
        sights: [sight_of(frames:)],
        of: set.from_list([2, 3, 9, 40]),
      )
      == removals
      as reason
  })
  let both = [
    sight_of(frames: [player_created(unit_id: 2), removed(unit_id: 2)]),
    sight_of(frames: [player_created(unit_id: 3), removed(unit_id: 3)]),
  ]
  assert load_sight.removals_read(sights: both, of: set.from_list([2, 3])) == 2
    as "the removals of the clients are added"
  assert load_sight.removals_read(sights: both, of: set.from_list([2])) == 1
    as "a player not among the units asked is not counted"
}

pub fn the_casting_scene_owes_each_probe_the_casts_that_finished_a_settle_time_before_the_end_test() -> Nil {
  use <- owned_test.run(5000)
  // Casts of 3,000 ms pressed at the times given, the probes reading until 12,000 ms: a
  // cast is owed once it finished 3,000 ms before that, as `load_respawn.needed` owes a
  // respawn for a death a settle time before the end.
  let rows = [
    #("two of four finished by 9,000", [1000, 4000, 8500, 9000], 2),
    #("a cast finished exactly a settle time before the end is owed", [6000], 1),
    #("a cast a millisecond later is not, the other is", [6001, 1000], 1),
    #("every cast finished in time", [0, 1000, 2000, 3000, 6000], 5),
    #("none finished in time is still one owed", [8000, 9000], 1),
    #("no cast at all is one owed", [], 1),
  ]
  list.each(rows, fn(row) {
    let #(reason, pressed_ms, owed) = row
    assert load_sight.casts_owed(
        pressed_ms:,
        duration_ms: 3000,
        ended_ms: 12_000,
        settle_ms: 3000,
      )
      == owed
      as reason
  })
  // Walkers 7 and 8 and a creature 40 cast. Walker 7's press is a cast and the child cast
  // it starts (casts 1 and 2); the sight was never told cast 99.
  let frames = [
    cast_started(cast_id: 1, caster: 7),
    cast_went(cast_id: 1),
    cast_started(cast_id: 2, caster: 7),
    cast_finished(cast_id: 2),
    cast_finished(cast_id: 1),
    cast_started(cast_id: 3, caster: 8),
    cast_finished(cast_id: 3),
    cast_started(cast_id: 4, caster: 40),
    cast_finished(cast_id: 4),
    cast_finished(cast_id: 99),
    moved(unit_id: 7, hundredths: 1),
  ]
  let sight = sight_of(frames:)
  let counted_for = fn(casters) {
    list.map([0x07FF, 0x07F4, 0x07FE], fn(message_id) {
      load_sight.cast_frames_read(
        sights: [sight],
        message_id:,
        casters: set.from_list(casters),
      )
    })
  }
  assert counted_for([7, 8]) == [3, 1, 3]
    as "the walkers' casts by kind: three starts, a go and three ends; a move and a cast never told are none"
  assert counted_for([7]) == [2, 1, 2]
    as "one walker's press is two starts and two ends, the cast and its child"
  assert counted_for([40]) == [1, 0, 1]
    as "a creature's cast is counted for the creature and not for the walkers"
  assert counted_for([]) == [0, 0, 0] as "no caster, no frame"
  // The sight reads frame n at n thousand microseconds (`sight_of`).
  assert list.sort(
      load_sight.held_us(sights: [sight], casters: set.from_list([7, 8])),
      int.compare,
    )
    == [1000, 1000, 4000]
    as "each cast read start to end is held from its 0x7ff to its 0x7fe: casts 2, 3 and 1; the cast never told is none"
  assert load_sight.held_us(sights: [sight], casters: set.from_list([40]))
    == [1000]
    as "a creature's cast is held for the creature alone"
}

pub fn the_pressed_ability_writes_a_viewer_the_frames_per_press_the_scene_owes_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4 32893, Telekinetic Strike, of Spell4Base 19102: a press with no target casts the
  // spell and each cast it starts on the caster alone (Spell4Effects Proxy rows with no
  // tickTime aimed at the caster, and theirs in turn), each a 0x7ff and a 0x7fe.
  let tables = fixture_tables.shared()
  let plans = spell_plan.plans(tables:)
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans:,
      base: Spell4BaseId(load_player.pressed_spell4_base_id),
    )
    as "the plans hold the pressed ability"
  assert spell.cast_time_ms == load_player.pressed_cast_ms
    as "Spell4 32893 has castTime 1250"
  assert casts_on_the_caster(spell:) == load_player.frames_per_press
    as "the casts of a press, the spell's own and those it starts on its caster"
}

fn casts_on_the_caster(spell spell: spell_plan.Spell) -> Int {
  1
  + int.sum(
    list.filter_map(spell.effects, fn(effect) {
      case spell_plan.as_proxy(effect.kind) {
        Ok(proxy)
          if proxy.target == spell_plan.OnCaster && proxy.period == option.None
        -> Ok(casts_on_the_caster(spell: proxy.spell))
        _ -> Error(Nil)
      }
    }),
  )
}

pub fn a_probe_waiting_for_the_others_keeps_every_frame_of_the_reads_it_makes_test() -> Nil {
  use <- owned_test.run(5000)
  // A probe reads its socket from its entry on, also while it waits for the others to
  // be in the world; the first move of a probe that began to send reaches it then, among
  // the frames of a read, and is as much a move it read as one read later. The deadline is
  // already past, so the probe reads once, as it does at its end.
  let probed = Probed(unit_id: 10, sent_us: dict.new(), seen: [])
  let #(_have, probed, sight) =
    load_move_delay.read_until(
      poll: fn(have, _wait_ms) {
        #(
          [
            player_created(unit_id: 20),
            moved(unit_id: 20, hundredths: 1),
            cast_started(cast_id: 5, caster: 20),
            moved(unit_id: 30, hundredths: 0),
          ],
          have,
        )
      },
      have: <<>>,
      until_us: load_sample.microseconds(),
      probed:,
      sight: load_sight.new(own_unit_id: 10),
    )
  assert list.map(probed.seen, fn(seen) { #(seen.0, seen.1) }) == [#(20, 1)]
    as "the probe's step 1 is among the moves read, the walker's move is not"
  assert load_sight.players_shown(sights: [sight]) == 1
    as "the player created in the same read is shown"
  assert load_sight.cast_frames_read(
      sights: [sight],
      message_id: 0x07FF,
      casters: set.from_list([20]),
    )
    == 1
    as "the cast frame of the same read is counted"
}

pub fn a_player_that_keeps_no_sight_opens_none_of_the_frames_it_is_written_test() -> Nil {
  use <- owned_test.run(5000)
  // The capacity ramp's players use no sight, and at thousands of players in sight of each
  // other opening every frame costs the clients more than the server's work they measure.
  let outers = [player_created(unit_id: 2), player_created(unit_id: 3)]
  assert load_player.read_into(
      open: fn(_) { panic as "a player that keeps no sight opened a frame" },
      sight: option.None,
      outers:,
    )
    == option.None
    as "no sight is kept, and no frame opened"
  let assert option.Some(sight) =
    load_player.read_into(
      open: fn(outers) { outers },
      sight: option.Some(load_sight.new(own_unit_id: 1)),
      outers:,
    )
    as "a player that keeps a sight reads each frame into it"
  assert load_sight.players_shown(sights: [sight]) == 2
    as "both players are shown"
}

pub fn the_maps_reductions_are_taken_between_the_samples_a_window_holds_test() -> Nil {
  use <- owned_test.run(5000)
  // Samples each 10 ms of a map that spent 1,000 reductions at 0 ms and 100 more each
  // sample.
  let probe =
    Probe(
      longest: 0,
      sum: 0,
      samples: 0,
      running: 0,
      series: [],
      taken: [],
      peak_memory_bytes: 0,
      reductions_series: list.repeat(Nil, 101)
        |> list.index_map(fn(_, index) { #(index * 10, 1000 + index * 100) }),
    )
  let rows = [
    #("a window of 500 ms is 50 samples' reductions", 100, 600, Ok(5000)),
    #(
      "a window between samples keeps the samples inside it",
      105,
      595,
      Ok(4800),
    ),
    #("a window of one sample is no window", 100, 109, Error(Nil)),
    #("a window after the last sample holds none", 2000, 3000, Error(Nil)),
  ]
  list.each(rows, fn(row) {
    let #(reason, from_ms, to_ms, expected) = row
    assert load_queue.reductions_between(probe:, from_ms:, to_ms:) == expected
      as reason
  })
  assert load_queue.per(total: 5000, count: 400) == "12.5"
    as "a mean to one decimal"
  assert load_queue.per(total: 5000, count: 0) == "-"
    as "a mean of none is a dash"
  assert load_queue.percent(part: 1, whole: 8) == "12.5%"
    as "a share to one decimal"
}
