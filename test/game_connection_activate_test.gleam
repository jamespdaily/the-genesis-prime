//// The activate cast on a running game connection: the map tells the connection which static
//// objects its player sees (`ObjectsSeen`), and the player's 0x97 right-click of one is
//// taken from the bytes to the cast rule. Expected values come from these places:
//// - `opcode.0x262`: the unit's creature id, place and display come from the object's 0x262.
//// - Creature2DisplayInfo 25703 (the Seaspine Mollusk's display) hitRadius 1.0, row 21397
////   hitRadius 2.0, Race 1 hitRadius 1.2: the edge of each unit the range is held to.
//// - Creature2 26462: activateSpellMaxRange 3.0, and its activate spell 1817 behind Prerequisite
////   9358, which a player with no challenge record passes.
//// - `opcode.0x97`: the message is the client's cast id and the unit; the client's cast id 0 is
////   refused by the client's own sender, so the connection ends.
//// - `opcode.0x7fd` and `opcode.0x7fc`: the caster is written a confirmation of a started cast
////   and a refusal of one that is not.
//// - Creature2 73605, the Departures Terminal: activateSpellCastTime 0, activate spell 34681,
////   Spell4Base 20651 of castMethod 5.
//// - `opcode.0x805` and `opcode.0x7f4`: the client's answer 1 to its interaction is followed
////   by the server's go and finish.

import connection_rule_support as support
import game_connection_support as connection_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/connection as game_connection
import genesis_prime/game/routing
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/cast_activate.{CastActivate}
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/interaction_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/step
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/map.{ObjectsSeen}
import genesis_prime/world_map/static_object.{type Created, StaticObject}
import gleam/list
import gleam/option
import owned_test
import spawn_support

const mollusk_display = 25_703

const display_of_radius_2 = 21_397

const nearby = 5000

const too_far_for_a_small_radius = 5001

const with_a_big_radius = 5002

const clients_cast_id = 9

/// The place `east` units east of where the tests' player stands (`entry_place`): the same
/// height and zone, so the gap between two units' edges is the distance less their radii.
fn east_of_the_player(east east: Float) -> Place {
  connection_support.standing_at(
    x: 29.128599166870117 +. east,
    y: -853.87158203125,
    z: -560.18798828125,
  )
}

/// A Seaspine Mollusk (Creature2 26462) as unit `unit_id`, `east` units east of the player,
/// shown with the display row.
fn mollusk(
  unit_id unit_id: Int,
  east east: Float,
  display display: Int,
) -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(
        number: unit_id,
        place: east_of_the_player(east:),
      ),
      creature_id: Creature2Id(26_462),
      display_info_id: display,
    ),
    unit_id:,
    server_time_estimate_start: 0,
  )
}

/// The bytes of the client's 0x97 right-click of `unit_id`, inside the client's 0x038C.
fn right_click_bytes(
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
) -> BitArray {
  let assert Ok(body) =
    cast_activate.encode(CastActivate(client_cast_id:, target_unit_id: unit_id))
    as "the message fits"
  connection_support.world_message(message_id: cast_activate.message_id, body:)
}

/// The connection's player has seen the three mollusks of the tests.
fn seeing_three_mollusks() -> game_connection.State {
  let #(state, _) =
    connection_support.feed(
      connection_support.in_world(),
      connection_support.sent_by_the_map(
        ObjectsSeen(units: [
          mollusk(unit_id: nearby, east: 5.0, display: mollusk_display),
          mollusk(
            unit_id: too_far_for_a_small_radius,
            east: 6.0,
            display: mollusk_display,
          ),
          mollusk(
            unit_id: with_a_big_radius,
            east: 6.0,
            display: display_of_radius_2,
          ),
        ]),
      ),
    )
  state
}

/// The ids of the frames the right-click of `unit_id` writes to its player.
fn written_by_the_click(unit_id unit_id: Int) -> List(Int) {
  let #(_, taken) =
    connection_support.read(
      state: seeing_three_mollusks(),
      bytes: right_click_bytes(client_cast_id: clients_cast_id, unit_id:),
    )
  connection_support.written_ids(taken)
}

const confirmed_start = [0x07FD]

const refused_start = [0x07FC]

pub fn objects_seen_hold_creature_place_and_radius_test() -> Nil {
  use <- owned_test.run(10_000)
  // Creature2 26462's activateSpellMaxRange is 3.0, so the cast starts when the gap between
  // the player's edge and the object's is 3.0 or less. The player's radius is Race 1's 1.2.
  assert written_by_the_click(unit_id: nearby) == confirmed_start
    as "opcode.0x262: the object's creature (26462: Prerequisite 9358 passes, spell 1817) and its place (5.0 east) reach the picture; the gap is 5.0 - 1.2 - 1.0 = 2.8 for display 25703's hitRadius 1.0, within 3.0"
  assert written_by_the_click(unit_id: too_far_for_a_small_radius)
    == refused_start
    as "the same object 6.0 east is 6.0 - 1.2 - 1.0 = 3.8 away: out of the creature's 3.0, refused (TargetRangeMax)"
  assert written_by_the_click(unit_id: with_a_big_radius) == confirmed_start
    as "6.0 east with display 21397's hitRadius 2.0 is 6.0 - 1.2 - 2.0 = 2.8 away: the display's own hit radius reaches the picture"
}

pub fn activate_frame_reaches_the_cast_rule_test() -> Nil {
  use <- owned_test.run(10_000)
  assert routing.route(
      routing.AtWorld,
      routing.InsideWorldMessage,
      cast_activate.message_id,
    )
    == Ok(routing.Activation)
    as "opcode.0x97: a 0x97 inside 0x038C is the activation row in the world"
  let #(_, taken) =
    connection_support.read(
      state: seeing_three_mollusks(),
      bytes: right_click_bytes(client_cast_id: clients_cast_id, unit_id: nearby),
    )
  let confirmations: List(Frame) =
    list.filter(
      connection_support.heard(taken:, cipher: connection_support.keyed()),
      fn(frame) { frame.message_id == spell_cast_confirmed.message_id },
    )
  let assert [confirmed] = confirmations
    as "the bytes of a 0x97 to the running connection give one 0x7fd"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  assert confirmed.client_cast_id == clients_cast_id
    && confirmed.primary_target_unit_id == nearby
    as "opcode.0x97: the confirmation answers the client's cast id and names the unit"
  let #(_, ended) =
    connection_support.read(
      state: seeing_three_mollusks(),
      bytes: right_click_bytes(client_cast_id: 0, unit_id: nearby),
    )
  assert option.is_some(support.asked(ended))
    as "opcode.0x97: the client never sends cast id 0, so the connection ends, and a connection with a player in the world saves its place first (an ask of the store)"
  assert connection_support.written_ids(ended) == []
    as "nothing is written to the client on the way out"
  assert list.length(support.logs_of(step: ended, level: step.LogError)) == 1
    as "the end is logged once as an error with the refusal's own words"
}

/// The Departures Terminal (Creature2 73605) as unit `nearby`, 3.0 east of the player.
fn terminal() -> Created {
  static_object.create(
    object: StaticObject(
      ..spawn_support.holoring(
        number: nearby,
        place: east_of_the_player(east: 3.0),
      ),
      creature_id: Creature2Id(73_605),
      display_info_id: mollusk_display,
    ),
    unit_id: nearby,
    server_time_estimate_start: 0,
  )
}

pub fn an_interaction_answer_reaches_the_cast_rule_test() -> Nil {
  use <- owned_test.run(10_000)
  assert routing.route(
      routing.AtWorld,
      routing.InsideWorldMessage,
      client_side_interaction_result.message_id,
    )
    == Ok(routing.Cast(message: cast.Answered))
    as "opcode.0x805: a 0x805 inside 0x038C is a cast row in the world"
  let #(seeing, _) =
    connection_support.feed(
      connection_support.in_world(),
      connection_support.sent_by_the_map(ObjectsSeen(units: [terminal()])),
    )
  let #(clicked, started) =
    connection_support.read(
      state: seeing,
      bytes: right_click_bytes(client_cast_id: clients_cast_id, unit_id: nearby),
    )
  assert connection_support.written_ids(started) == confirmed_start
    as "opcode.0x7fd.csi: the right-click of the terminal writes the start, and no go yet: the cast waits for the client's answer"
  let assert [confirmed] =
    list.filter(
      connection_support.heard(
        taken: started,
        cipher: connection_support.keyed(),
      ),
      fn(frame) { frame.message_id == spell_cast_confirmed.message_id },
    )
  let assert Ok(confirmed) = spell_cast_confirmed.decode(confirmed.body)
  let assert Ok(body) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id: confirmed.server_cast_id,
      result: interaction_result.Succeeded,
      spell4_base_id_plus_one: 20_652,
    ))
    as "the answer fits the message"
  let #(_, answered) =
    connection_support.read(
      state: clicked,
      bytes: connection_support.world_message(
        message_id: client_side_interaction_result.message_id,
        body:,
      ),
    )
  assert connection_support.written_ids(answered) == [0x07F4, 0x07FE]
    as "opcode.0x805, opcode.0x7f4: the answer 1 sends the go and the finish to the player"
}
