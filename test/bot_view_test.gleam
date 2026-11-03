//// The scripted client's view of other players (`game_client.observe`): the
//// messages the server writes for another player's unit create it, move it and
//// remove it as the client's own unit table does. Expected values come from
//// these places.
//// - 0x262 creates the unit at its kind 2 position (0x1404586e0); 0x638 applies
////   its commands in order, so the position a unit holds is the last kind 2 it
////   was given (0x140787150); a 0x638 for a unit the client does not hold is
////   dropped and the connection goes on (opcode.0x638); 0x355 removes the unit
////   (0x1403d98f0).
//// - The commands and the positions are chosen by the test: x, y, z of 1.0,
////   2.0, 3.0 at the start, 4.0, 5.0, 6.0 then 7.0, 8.0, 9.0 in one 0x638.

import character_support
import game_client
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/float32
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/world_map/player_unit
import gleam/dict
import owned_test
import place_support

fn created(unit_id unit_id: Int, x x: Float) -> Frame {
  let place =
    place_support.at(world_id: 3460, world_zone_id: 6009, x:, y: 2.0, z: 3.0)
  let record =
    player_unit.create(
      unit: player_unit.new(
        character: character_support.character(number: unit_id),
        place:,
        unit_id:,
        visuals: [],
      ),
      realm_id: 1,
    )
  let assert Ok(body) = unit_create_player.encode(record) as "0x262 encodes"
  Frame(message_id: 0x0262, body:)
}

fn position(
  x x: Float,
  y y: Float,
  z z: Float,
) -> relayed_movement.RelayedMovement {
  relayed_movement.Position(UnitPositionCommand(
    x: float32.to_bits(x),
    y: float32.to_bits(y),
    z: float32.to_bits(z),
    blends: 1,
  ))
}

fn moved(
  unit_id unit_id: Int,
  commands commands: List(relayed_movement.RelayedMovement),
) -> Frame {
  let assert Ok(body) =
    unit_movement.encode(UnitMovement(
      unit_id:,
      server_time: 10,
      reset_movement: 0,
      kept: 0,
      commands:,
    ))
    as "0x638 encodes"
  Frame(message_id: 0x0638, body:)
}

fn removed(unit_id: Int) -> Frame {
  let assert Ok(body) =
    unit_destroyed.encode(UnitDestroyed(unit_id:, field_2: 0))
    as "0x355 encodes"
  Frame(message_id: 0x0355, body:)
}

pub fn the_bots_model_of_another_player_is_created_moved_to_its_last_kind_2_position_and_removed_test() -> Nil {
  use <- owned_test.run(5000)
  let others = dict.new()
  let others = game_client.observe(others:, frame: created(unit_id: 9, x: 1.0))
  assert others == dict.from_list([#(9, #(1.0, 2.0, 3.0))])
    as "0x262 creates the unit at its kind 2 position"
  let others =
    game_client.observe(
      others:,
      frame: moved(unit_id: 9, commands: [
        position(x: 4.0, y: 5.0, z: 6.0),
        relayed_movement.Mode(MovementMode(mode: 1)),
        position(x: 7.0, y: 8.0, z: 9.0),
        relayed_movement.Mode(MovementMode(mode: 3)),
      ]),
    )
  assert others == dict.from_list([#(9, #(7.0, 8.0, 9.0))])
    as "the kind 2 positions apply in order, so the unit stands at the last"
  let others =
    game_client.observe(
      others:,
      frame: moved(unit_id: 77, commands: [position(x: 0.0, y: 0.0, z: 0.0)]),
    )
  assert others == dict.from_list([#(9, #(7.0, 8.0, 9.0))])
    as "a 0x638 for a unit the client does not hold changes nothing"
  let others =
    game_client.observe(others:, frame: created(unit_id: 10, x: 50.0))
  assert dict.size(others) == 2
  let others = game_client.observe(others:, frame: removed(9))
  assert others == dict.from_list([#(10, #(50.0, 2.0, 3.0))])
    as "0x355 removes the unit and no other"
  let others =
    game_client.observe(others:, frame: Frame(message_id: 0x0061, body: <<>>))
  assert dict.size(others) == 1 as "any other message changes nothing"
}
