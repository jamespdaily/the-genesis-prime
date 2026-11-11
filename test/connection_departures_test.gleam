//// The departures timer on a game connection that is no longer in the world it counted
//// the departure in. Expected values come from these places.
//// - `opcode.0xbf` and `opcode.0xc0`: the camp the player ends the stay with.
//// - Creature2 73606's activate spell 34680, Spell4Base 20650 (the client's 0x805 carries the
////   id plus one: `opcode.0x805.fields`).
//// - The server's rule that a move is made only for a player in the world and alive: a
////   departure the connection can no longer carry out moves nothing and tells nothing.
//// - The connection's statuses that hold the player while an ask is out or the claim of the
////   account waits (`connection/state.standing`): the player is still the one that said yes,
////   so the departure waits for the connection to stand in the world again.

import connection_rule_support as support
import departures_support
import game_connection_support as connection_support
import genesis_prime/account_session.{Claimed}
import genesis_prime/client_connection.{FromSessions}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/departures
import genesis_prime/step.{OwnEvent, TimerFired, TimerId, WatchEnded, WatchId}
import gleam/option.{None}
import owned_test

const northern_wilds = 73_606

const northern_wilds_spell4_base = 20_650

/// `state` after the yes at the Northern Wilds terminal.
fn after_the_yes() -> game_connection.State {
  departures_support.yes(
    state: departures_support.exile_seeing(creature_id: northern_wilds),
    spell4_base_id: northern_wilds_spell4_base,
  ).0
}

pub fn a_departure_due_after_the_stay_ended_moves_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let camped = connection_support.camp_from(after_the_yes())
  let #(_, fired) = departures_support.timer_fires(state: camped)
  assert support.effects_of(fired) == []
    as "a connection back in character select has no stay to leave: the due timer does nothing"
  assert support.asked(fired) == None as "and asks no map"
  let #(dead, _) = connection_support.killed(after_the_yes())
  let #(_, fired_dead) = departures_support.timer_fires(state: dead)
  assert support.effects_of(fired_dead) == []
    as "a dead player is not moved: the due timer does nothing"
  assert support.asked(fired_dead) == None as "and asks no map"
  let #(_, fired_unbidden) =
    departures_support.timer_fires(state: departures_support.exile_seeing(
      creature_id: northern_wilds,
    ))
  assert support.effects_of(fired_unbidden) == []
    as "a due timer when no departure was counted moves nothing"
  assert support.asked(fired_unbidden) == None as "and asks no map"
}

pub fn a_departure_due_while_the_connection_waits_starts_the_timer_again_test() -> Nil {
  use <- owned_test.run(60_000)
  // Sessions ended after the yes: the connection waits on its claim timer, holding the
  // player, when the departure's timer fires.
  let #(waiting, _) =
    connection_support.feed(
      state: after_the_yes(),
      event: WatchEnded(WatchId(1)),
    )
  let #(waiting, fired) = departures_support.timer_fires(state: waiting)
  let assert [#(timer, after_ms)] =
    departures_support.started_timers(taken: fired)
    as "the timer that found the connection not standing in the world is started again"
  assert departures.owns(timer)
  assert after_ms > 0
    as "after a wait, so the connection does not spin while the claim is out"
  assert support.asked(fired) == None as "and no map is asked yet"
  // The claim is made again and answered: the player stands in the world again.
  let #(claiming, claim) =
    connection_support.feed(
      state: waiting,
      event: OwnEvent(TimerFired(TimerId(1))),
    )
  let #(standing, _) =
    connection_support.answer(
      state: claiming,
      taken: claim,
      outcome: step.Answer(FromSessions(Claimed)),
    )
  let #(_, leaving) = departures_support.timer_fires(state: standing)
  assert connection_support.ask_request(leaving)
    == connection_support.leave_asked()
    as "the restarted timer finds the player in the world with the landing kept: the leave begins"
}
