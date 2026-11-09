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
import genesis_prime/world_map/static_object
import gleam/dict
import gleam/list
import message_support
import owned_test
import place_support
import unit_support

fn created(unit_id unit_id: Int, x x: Float) -> Frame {
  let place =
    place_support.at(world_id: 3460, world_zone_id: 6009, x:, y: 2.0, z: 3.0)
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

pub fn the_bot_takes_a_static_objects_0x262_as_an_object_and_not_a_creature_test() -> Nil {
  use <- owned_test.run(5000)
  // The vectors of `combat_message_vector_test` for types 10, 11 and 32
  // (opcode.0x262.simple), units 0x2001 to 0x2003, each at (-131.5, -875.25,
  // 333.5).
  let frames =
    list.map(
      [
        "01 20 00 00 ca fa 47 00 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
        "02 20 00 00 cb 5c 46 04 00 41 11 00 00 00 00 00 00 00 20 04 00 e0 c0 30 00 b4 16 31 00 b0 e9 10 07 00 00 fc 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 b4 10 2d 00 00 00 00 00 00 00 00 00 00 00 00 50 e2 59 d1 48 a4 0d 00 00 8d 14 00 00 00 00 00 00 00 40 f1 19 15 00",
        "03 20 00 00 20 c7 47 00 00 02 a0 1b 00 00 a0 18 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 10 70 00 00 d0 3d 04 00 d0 3d 04 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
      ],
      fn(hex) { Frame(message_id: 0x0262, body: message_support.hex(hex)) },
    )
  assert game_client.creatures_created_in(frames:) == []
    as "no static object is taken as a creature"
  assert list.map(frames, fn(frame) {
      case game_client.created_unit(body: frame.body) {
        Ok(game_client.ObjectCreated(unit_type:, ..)) -> Ok(unit_type)
        Ok(game_client.PlayerCreated(..))
        | Ok(game_client.CreatureCreated(..))
        | Error(Nil) -> Error(Nil)
      }
    })
    == [
      Ok(static_object.Simple),
      Ok(static_object.Platform),
      Ok(static_object.SimpleCollidable),
    ]
    as "each is an object of its type"
  let others =
    list.fold(frames, dict.new(), fn(others, frame) {
      game_client.observe(others:, frame:)
    })
  assert others
    == dict.from_list([
      #(0x2001, #(-131.5, -875.25, 333.5)),
      #(0x2002, #(-131.5, -875.25, 333.5)),
      #(0x2003, #(-131.5, -875.25, 333.5)),
    ])
    as "the client holds each object at its kind 2 position (0x1404586e0)"
}
