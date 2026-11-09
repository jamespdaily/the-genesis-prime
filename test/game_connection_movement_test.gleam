//// The game connection's rule (`genesis_prime/game/connection`), run as the pure function
//// it is: inputs in, new state and effects out. These tests cover what the client's
//// zone reports (terrain loaded 0xf2, zone changed 0x63a) make the connection write
//// beside the zone channel: the zone's welcome (genesis_prime/game/zone_welcome).
////
//// Expected values come from the client: 0x179 is the message number the client reads a
//// Tutorial id from (`opcode.0x179`, one 32-bit value, least significant byte first,
//// so Tutorial 332 is 4c 01 00 00), and the client sends 0xf2 after the world entry burst
//// (`opcode.0xf2`).

import connection_rule_support as support
import game_connection_support
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/store.{Character}
import gleam/list
import gleam/option.{Some}
import owned_test
import place_support
import zone_welcome_support

pub fn terrain_loaded_in_a_welcome_zone_sends_server_tutorial_after_the_entry_burst_test() -> Nil {
  use <- owned_test.run(10_000)
  let settings =
    Settings(
      ..game_connection_support.settings(),
      zone_welcomes: zone_welcome_support.landings(),
    )
  let landing =
    Character(
      ..game_connection_support.world_character(),
      place: Some(place_support.at(
        world_id: 3460,
        world_zone_id: 648,
        x: 29.128599166870117,
        y: -853.87158203125,
        z: -560.18798828125,
      )),
    )
  let #(entered, burst) =
    game_connection_support.entered_from(
      in_character_select: game_connection_support.in_select_from(
        game_connection_support.accepted(settings).0,
      ),
      character: landing,
    )
  assert !list.contains(game_connection_support.written_ids(burst), 0x0179)
    as "opcode.0xf2: the player is in zone 648 from the burst, which writes no welcome; the client's 0xf2 is the trigger"
  let #(_, loaded) =
    game_connection_support.read(
      entered,
      game_connection_support.terrain_loaded_message(648),
    )
  assert game_connection_support.written_ids(loaded) == [0x01BC, 0x0179]
    as "chat.zone_reach: the place's own zone needs no 0x1da, so the first 0xf2 writes the zone channel's 0x1bc as before, then the welcome"
  assert list.last(game_connection_support.written(taken: loaded))
    == Ok(Frame(message_id: 0x0179, body: <<0x4c, 0x01, 0x00, 0x00>>))
    as "0x179 carries Tutorial 332, the Northern Wilds welcome of WorldZone 648"
  assert support.logs(loaded) == [] && !support.stops(loaded)
  let #(_, walked) =
    game_connection_support.read(
      entered,
      game_connection_support.zone_changed_message(old: 648, new: 593),
    )
  assert list.last(game_connection_support.written(taken: walked))
    == Ok(Frame(message_id: 0x0179, body: <<0xe9, 0x00, 0x00, 0x00>>))
    as "opcode.0x63a: walking from 648 into Settler's Reach (WorldZone 593) writes 0x179 with Tutorial 233, 0xe9"
  let #(_, within) =
    game_connection_support.read(
      entered,
      game_connection_support.zone_changed_message(old: 648, new: 648),
    )
  assert !list.contains(game_connection_support.written_ids(within), 0x0179)
    as "opcode.0x63a: old equal to new keeps the welcome"
}
