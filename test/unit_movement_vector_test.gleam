//// Message 0x0638 against the client's own bytes: the fact file's
//// `vector.opcode.0x638.body`, the body the client's reader (0x1400b03a0) takes
//// in all 275 bits on the p-code emulator: unit id 0x1001, server time
//// 0x12345678, reset bit 0, kept bit 0, count 2, then a kind 2 at (1.0, 2.0,
//// -3.0) with its bit set and a kind 14 at (1.5, 0.0, 0.0) with its bit set.
//// A float is kept as its bits in the codec: 1.0 is 0x3F800000, 2.0 is
//// 0x40000000, -3.0 is 0xC0400000 and 1.5 is 0x3FC00000 (IEEE 754 binary32).

import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_timed_path.{MovementTimedPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import message_support
import owned_test
import qcheck

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
    must_encode: unit_movement.must_encode,
    decode: unit_movement.decode,
  )
}

pub fn kind_3_relayed_movement_round_trips_test() -> Nil {
  use <- owned_test.run(60_000)
  let word = qcheck.bounded_int(from: 0, to: 0xFFFFFFFF)
  let counts =
    qcheck.from_weighted_generators(#(8, qcheck.bounded_int(from: 0, to: 12)), [
      #(1, qcheck.return(1023)),
    ])
  let generator = {
    use count <- qcheck.bind(counts)
    qcheck.tuple2(
      qcheck.fixed_length_list_from(word, count),
      qcheck.fixed_length_list_from(
        qcheck.map3(word, word, word, MovementFloatVector),
        count,
      ),
    )
  }
  use #(times, points) <- qcheck.given(generator)
  let value =
    UnitMovement(
      unit_id: 0x2001,
      server_time: 0xFF00,
      reset_movement: 0,
      kept: 0,
      commands: [
        relayed_movement.TimedPath(MovementTimedPath(times:, points:)),
      ],
    )
  let assert Ok(body) = unit_movement.encode(value)
    as "movement_command.kind_3: any count up to 1023 of times and points, each a 32-bit word, is written"
  assert unit_movement.decode(body) == Ok(value)
    as "movement_command.kind_3: the count, the times and the points read back as they were written"
}
