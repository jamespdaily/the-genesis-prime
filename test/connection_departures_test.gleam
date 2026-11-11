//// The departures timer on a game connection that is no longer in the world it counted
//// the departure in. Expected values come from these places.
//// - `opcode.0xbf` and `opcode.0xc0`: the camp the player ends the stay with.
//// - Creature2 73606's activate spell 34680, Spell4Base 20650 (the client's 0x805 carries the
////   id plus one: `opcode.0x805.fields`).
//// - The server's rule that a move is made only for a player in the world and alive: a
////   departure the connection can no longer carry out moves nothing and tells nothing.

import connection_rule_support as support
import departures_support
import game_connection_support as connection_support
import genesis_prime/game/connection as game_connection
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
