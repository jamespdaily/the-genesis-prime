//// Message 0x0638 against the client's own bytes: the fact file's
//// `vector.opcode.0x638.body`, the body the client's reader (0x1400b03a0) takes
//// in all 275 bits on the p-code emulator: unit id 0x1001, server time
//// 0x12345678, reset bit 0, kept bit 0, count 2, then a kind 2 at (1.0, 2.0,
//// -3.0) with its bit set and a kind 14 at (1.5, 0.0, 0.0) with its bit set.
//// A float is kept as its bits in the codec: 1.0 is 0x3F800000, 2.0 is
//// 0x40000000, -3.0 is 0xC0400000 and 1.5 is 0x3FC00000 (IEEE 754 binary32).

import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import message_support
import owned_test

pub fn unit_movement_is_the_clients_275_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  message_support.assert_vector(
    name: "vector.opcode.0x638.body",
    body: message_support.hex(
      "011000007856341208010000f80300000004000004dc010000ff000000000000000004",
    ),
    value: UnitMovement(
      unit_id: 0x1001,
      server_time: 0x12345678,
      reset_movement: 0,
      kept: 0,
      commands: [
        relayed_movement.Position(UnitPositionCommand(
          x: 0x3F800000,
          y: 0x40000000,
          z: 0xC0400000,
          blends: 1,
        )),
        relayed_movement.Rotation(MovementRotation(
          yaw: 0x3FC00000,
          pitch: 0,
          roll: 0,
          blends: 1,
        )),
      ],
    ),
    encode: unit_movement.encode,
    decode: unit_movement.decode,
  )
}
