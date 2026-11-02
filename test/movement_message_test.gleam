//// The messages of the player moving that the client sends in the world:
//// 0x637 with its list of movement commands, and 0x63A, 0xD5, 0x63B, 0xFB and
//// 0xFC. Expected values come from these places.
//// - The fact file's `vector.opcode.0x637.body`: the bytes the client's own
////   writer gives for clock 0x1234 and three commands (a time of 0x1335, a
////   position (1.0, 2.0, -3.0) with its bit set, a kind 8 of the half floats
////   1.0, 0.0 and -1.0 with its bit set), run by the emulator.
//// - The fact `0x140c1f070`: the layout of each command kind 0 to 29 in wire
////   order, which every kind's bytes below are packed by with the packer in
////   this file, written for the test and no part of the codec, so a field read
////   at the wrong width or in the wrong place shows. A kind of 30 or more fails
////   the client's reader (`0x1400af930`), and so does a count that promises
////   more commands than the bytes hold (`0x1400b06f0`).
//// - The facts `opcode.0x63a`, `opcode.0xd5`, `opcode.0x63b`, `opcode.0xfb` and
////   `opcode.0xfc`: the widths of each message's values in wire order.
//// - The IEEE 754 binary32 and binary16 patterns: 1.0 is 0x3F800000 and 0x3C00,
////   2.0 is 0x40000000, -3.0 is 0xC0400000, -1.0 is 0xBC00, and an exponent of
////   all ones with a zero fraction is infinity, 0x7C00 in 16 bits.

import genesis_prime/message/bit_stream
import genesis_prime/message/client_message
import genesis_prime/message/fall_value.{FallValue}
import genesis_prime/message/fell_below_floor.{FellBelowFloor}
import genesis_prime/message/half_float.{Finite, Infinite}
import genesis_prime/message/move_speed_setting.{MoveSpeedSetting}
import genesis_prime/message/movement_command.{
  type MovementCommand, Kind10, Kind12, Kind13, Kind15, Kind16, Kind17, Kind18,
  Kind19, Kind20, Kind21, Kind22, Kind23, Kind25, Kind26, Kind28, Kind29, Kind3,
  Kind4, Kind5, Kind6, Kind7, Kind9, Mode, MoveAsked, Platform, Position,
  Rotation, StateFlags, Time, Velocity,
}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_half_vector.{MovementHalfVector}
import genesis_prime/message/movement_kind_10.{MovementKind10}
import genesis_prime/message/movement_kind_12.{MovementKind12}
import genesis_prime/message/movement_kind_13.{MovementKind13}
import genesis_prime/message/movement_kind_15.{MovementKind15}
import genesis_prime/message/movement_kind_16.{MovementKind16}
import genesis_prime/message/movement_kind_17.{MovementKind17}
import genesis_prime/message/movement_kind_18.{MovementKind18}
import genesis_prime/message/movement_kind_19.{MovementKind19}
import genesis_prime/message/movement_kind_20.{MovementKind20}
import genesis_prime/message/movement_kind_21.{MovementKind21}
import genesis_prime/message/movement_kind_22.{MovementKind22}
import genesis_prime/message/movement_kind_23.{MovementKind23}
import genesis_prime/message/movement_kind_25.{MovementKind25}
import genesis_prime/message/movement_kind_26.{MovementKind26}
import genesis_prime/message/movement_kind_28.{MovementKind28}
import genesis_prime/message/movement_kind_29.{MovementKind29}
import genesis_prime/message/movement_kind_3.{MovementKind3}
import genesis_prime/message/movement_kind_4.{MovementKind4}
import genesis_prime/message/movement_kind_5.{MovementKind5}
import genesis_prime/message/movement_kind_6.{MovementKind6}
import genesis_prime/message/movement_kind_7.{MovementKind7}
import genesis_prime/message/movement_kind_9.{MovementKind9}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_send_interval_answer.{
  MovementSendIntervalAnswer,
}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_velocity.{MovementVelocity}
import genesis_prime/message/player_movement.{PlayerMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/zone_value_changed.{ZoneValueChanged}
import gleam/int
import gleam/list
import message_support
import owned_test

// ---- the packer: the bits of a body, value by value, written for the test ----

/// A value and the number of bits it takes.
type Bits =
  #(Int, Int)

fn u32(value: Int) -> Bits {
  #(32, value)
}

fn bit(value: Int) -> Bits {
  #(1, value)
}

fn half(value: Int) -> Bits {
  #(16, value)
}

/// The bytes of the values laid end to end, the first value in the lowest bits
/// and the last byte padded with zero bits, as the client's bit stream does.
fn packed(values: List(Bits)) -> BitArray {
  let #(number, total) =
    list.fold(values, #(0, 0), fn(state, value) {
      let #(number, used) = state
      let #(width, bits) = value
      #(number + bits * pow2(used), used + width)
    })
  let bytes = { total + 7 } / 8
  <<number:size({ bytes * 8 })-little>>
}

fn pow2(exponent: Int) -> Int {
  int.bitwise_shift_left(1, exponent)
}

/// The body of a 0x637 holding `commands`, each its kind (5 bits) and data.
fn movement_body(commands: List(#(Int, List(Bits)))) -> BitArray {
  packed([
    u32(0x1234),
    u32(list.length(commands)),
    ..list.flat_map(commands, fn(command) { [#(5, command.0), ..command.1] })
  ])
}

// ---- test 2: the vector the client's writer gives ----

pub fn the_clients_0x637_vector_is_a_clock_and_three_commands_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x637.body",
    body: message_support.hex(
      "3412000003000000a066020040000000fe000000000100000147003c000000bc01",
    ),
    value: PlayerMovement(client_clock: 0x1234, commands: [
      Time(MovementTime(time: 0x1335)),
      Position(UnitPositionCommand(
        x: 0x3F800000,
        y: 0x40000000,
        z: 0xC0400000,
        blends: 1,
      )),
      Velocity(MovementVelocity(x: 0x3C00, y: 0, z: 0xBC00, field_5: 1)),
    ]),
    encode: player_movement.encode,
    decode: player_movement.decode,
  )
}

// ---- test 3: every kind by its layout ----

/// A kind's data in wire order after its 5 bits, and the command it reads as.
type Kind {
  Kind(kind: Int, data: List(Bits), command: MovementCommand)
}

fn float_vectors() -> List(movement_float_vector.MovementFloatVector) {
  [
    MovementFloatVector(field_1: 0x3F800001, field_2: 0x40000002, field_3: 3),
    MovementFloatVector(field_1: 4, field_2: 0xC0400005, field_3: 6),
  ]
}

fn float_vector_data() -> List(Bits) {
  [u32(0x3F800001), u32(0x40000002), u32(3), u32(4), u32(0xC0400005), u32(6)]
}

fn half_vectors() -> List(movement_half_vector.MovementHalfVector) {
  [
    MovementHalfVector(field_1: 0x3C00, field_2: 0xBC00, field_3: 0x7C00),
    MovementHalfVector(field_1: 4, field_2: 5, field_3: 0xFFFF),
  ]
}

fn half_vector_data() -> List(Bits) {
  [half(0x3C00), half(0xBC00), half(0x7C00), half(4), half(5), half(0xFFFF)]
}

/// Each kind 0 to 29 with data that gives every field its own value, laid out
/// as the fact `0x140c1f070` lists it.
fn kinds() -> List(Kind) {
  [
    Kind(0, [u32(0x1335)], Time(MovementTime(time: 0x1335))),
    Kind(1, [u32(0x01020304)], Platform(MovementPlatform(unit_id: 0x01020304))),
    Kind(
      2,
      [u32(0x3F800000), u32(0x40000000), u32(0xC0400000), bit(1)],
      Position(UnitPositionCommand(
        x: 0x3F800000,
        y: 0x40000000,
        z: 0xC0400000,
        blends: 1,
      )),
    ),
    Kind(
      3,
      list.flatten([
        [#(10, 2), u32(11), u32(12)],
        float_vector_data(),
        [#(2, 3), u32(31), bit(1)],
      ]),
      Kind3(MovementKind3(
        field_2: [11, 12],
        field_3: float_vectors(),
        field_4: 3,
        field_5: 31,
        field_6: 1,
      )),
    ),
    Kind(
      4,
      list.flatten([
        [#(10, 2)],
        float_vector_data(),
        [#(16, 0xABCD), #(2, 2), #(4, 9), u32(77), bit(1)],
      ]),
      Kind4(MovementKind4(
        field_2: float_vectors(),
        field_3: 0xABCD,
        field_4: 2,
        field_5: 9,
        field_6: 77,
        field_7: 1,
      )),
    ),
    Kind(
      5,
      [
        u32(1),
        u32(0x3F800002),
        u32(0x3F800003),
        half(4),
        half(5),
        half(6),
        #(4, 7),
        u32(8),
        bit(1),
        bit(0),
        bit(1),
      ],
      Kind5(MovementKind5(
        field_2: 1,
        field_3: 0x3F800002,
        field_4: 0x3F800003,
        field_5: 4,
        field_6: 5,
        field_7: 6,
        field_8: 7,
        field_9: 8,
        field_10: 1,
        field_11: 0,
        field_12: 1,
      )),
    ),
    Kind(
      6,
      [
        #(10, 2),
        u32(21),
        u32(22),
        #(16, 23),
        u32(0x3F800024),
        u32(0x3F800025),
        u32(0x3F800026),
        half(27),
        half(28),
        half(29),
        #(4, 5),
        u32(31),
        u32(32),
        bit(1),
        bit(0),
      ],
      Kind6(MovementKind6(
        field_2: [21, 22],
        field_3: 23,
        field_4: 0x3F800024,
        field_5: 0x3F800025,
        field_6: 0x3F800026,
        field_7: 27,
        field_8: 28,
        field_9: 29,
        field_10: 5,
        field_11: 31,
        field_12: 32,
        field_13: 1,
        field_14: 0,
      )),
    ),
    Kind(
      7,
      [
        u32(0x3F800001),
        u32(0x3F800002),
        u32(0x3F800003),
        u32(0x3F800004),
        u32(0x3F800005),
        u32(0x3F800006),
        u32(7),
        u32(0x3F800008),
        u32(9),
        bit(1),
      ],
      Kind7(MovementKind7(
        field_2: 0x3F800001,
        field_3: 0x3F800002,
        field_4: 0x3F800003,
        field_5: 0x3F800004,
        field_6: 0x3F800005,
        field_7: 0x3F800006,
        field_8: 7,
        field_9: 0x3F800008,
        field_10: 9,
        field_11: 1,
      )),
    ),
    Kind(
      8,
      [half(0x3C00), half(0), half(0xBC00), bit(1)],
      Velocity(MovementVelocity(x: 0x3C00, y: 0, z: 0xBC00, field_5: 1)),
    ),
    Kind(
      9,
      list.flatten([
        [#(10, 2), u32(41), u32(42)],
        half_vector_data(),
        [#(2, 2), u32(43), bit(1)],
      ]),
      Kind9(MovementKind9(
        field_2: [41, 42],
        field_3: half_vectors(),
        field_4: 2,
        field_5: 43,
        field_6: 1,
      )),
    ),
    Kind(10, [bit(1)], Kind10(MovementKind10(field_2: 1))),
    Kind(
      11,
      [half(0x3C00), half(0xBC00), half(0x7C00), bit(0)],
      MoveAsked(MovementMoveAsked(x: 0x3C00, y: 0xBC00, z: 0x7C00, field_5: 0)),
    ),
    Kind(
      12,
      list.flatten([
        [#(10, 2), u32(51), u32(52)],
        half_vector_data(),
        [#(2, 1), u32(53), bit(0)],
      ]),
      Kind12(MovementKind12(
        field_2: [51, 52],
        field_3: half_vectors(),
        field_4: 1,
        field_5: 53,
        field_6: 0,
      )),
    ),
    Kind(13, [bit(0)], Kind13(MovementKind13(field_2: 0))),
    Kind(
      14,
      [u32(0x3F800001), u32(0xBF800002), u32(0), bit(1)],
      Rotation(MovementRotation(
        yaw: 0x3F800001,
        pitch: 0xBF800002,
        roll: 0,
        blends: 1,
      )),
    ),
    Kind(
      15,
      list.flatten([
        [#(10, 2), u32(61), u32(62)],
        float_vector_data(),
        [#(2, 0), u32(63), bit(1)],
      ]),
      Kind15(MovementKind15(
        field_2: [61, 62],
        field_3: float_vectors(),
        field_4: 0,
        field_5: 63,
        field_6: 1,
      )),
    ),
    Kind(
      16,
      [u32(1), #(16, 2), u32(0x3F800003), #(4, 4), u32(5), bit(1), bit(0)],
      Kind16(MovementKind16(
        field_2: 1,
        field_3: 2,
        field_4: 0x3F800003,
        field_5: 4,
        field_6: 5,
        field_7: 1,
        field_8: 0,
      )),
    ),
    Kind(
      17,
      [
        #(10, 2),
        u32(71),
        u32(72),
        #(16, 73),
        u32(0x3F800074),
        u32(0x3F800075),
        u32(0x3F800076),
        #(4, 6),
        u32(77),
        u32(78),
        bit(1),
      ],
      Kind17(MovementKind17(
        field_2: [71, 72],
        field_3: 73,
        field_4: 0x3F800074,
        field_5: 0x3F800075,
        field_6: 0x3F800076,
        field_7: 6,
        field_8: 77,
        field_9: 78,
        field_10: 1,
      )),
    ),
    Kind(
      18,
      [u32(0xFFFFFFFF), bit(1)],
      Kind18(MovementKind18(field_2: 0xFFFFFFFF, field_3: 1)),
    ),
    Kind(
      19,
      [u32(0x3F800001), u32(0x3F800002), u32(0x3F800003), bit(1)],
      Kind19(MovementKind19(
        field_2: 0x3F800001,
        field_3: 0x3F800002,
        field_4: 0x3F800003,
        field_5: 1,
      )),
    ),
    Kind(
      20,
      [
        u32(0x3F800001),
        u32(0x3F800002),
        u32(0x3F800003),
        u32(4),
        #(16, 5),
        u32(6),
        bit(1),
      ],
      Kind20(MovementKind20(
        field_2: 0x3F800001,
        field_3: 0x3F800002,
        field_4: 0x3F800003,
        field_5: 4,
        field_6: 5,
        field_7: 6,
        field_8: 1,
      )),
    ),
    Kind(21, [bit(1)], Kind21(MovementKind21(field_2: 1))),
    Kind(
      22,
      [#(16, 0x1234), bit(1)],
      Kind22(MovementKind22(field_2: 0x1234, field_3: 1)),
    ),
    Kind(
      23,
      [
        #(8, 2),
        u32(81),
        u32(82),
        #(16, 83),
        #(16, 84),
        #(2, 3),
        u32(85),
        bit(1),
      ],
      Kind23(MovementKind23(
        field_2: [81, 82],
        field_3: [83, 84],
        field_4: 3,
        field_5: 85,
        field_6: 1,
      )),
    ),
    Kind(24, [u32(0x3FFFF)], StateFlags(MovementStateFlags(flags: 0x3FFFF))),
    Kind(
      25,
      [#(8, 2), u32(91), u32(92), u32(93), u32(94), u32(95)],
      Kind25(MovementKind25(field_2: [91, 92], field_3: [93, 94], field_4: 95)),
    ),
    Kind(26, [bit(0)], Kind26(MovementKind26(field_2: 0))),
    Kind(27, [u32(3)], Mode(MovementMode(mode: 3))),
    Kind(
      28,
      [#(8, 1), u32(101), u32(102), u32(103)],
      Kind28(MovementKind28(field_2: [101], field_3: [102], field_4: 103)),
    ),
    Kind(29, [bit(1)], Kind29(MovementKind29(field_2: 1))),
  ]
}

pub fn each_command_kind_0_to_29_is_read_by_its_layout_test() -> Nil {
  use <- owned_test.run(10_000)
  assert list.map(kinds(), fn(kind) { kind.kind })
    == int.range(from: 29, to: -1, with: [], run: fn(numbers, number) {
      [number, ..numbers]
    })
    as "0x140c1f070: the table holds a reader for each kind 0 to 29, and the test has a case for each"
  list.each(kinds(), fn(kind) {
    message_support.assert_codec(
      name: "kind " <> int.to_string(kind.kind) <> " by 0x140c1f070",
      body: movement_body([#(kind.kind, kind.data)]),
      value: PlayerMovement(client_clock: 0x1234, commands: [kind.command]),
      encode: player_movement.encode,
      decode: player_movement.decode,
    )
  })
}

pub fn all_thirty_kinds_in_one_message_are_read_each_after_the_one_before_test() -> Nil {
  use <- owned_test.run(10_000)
  let body =
    movement_body(list.map(kinds(), fn(kind) { #(kind.kind, kind.data) }))
  message_support.assert_codec(
    name: "the 30 kinds, one after the other, so each starts at another bit of a byte",
    body:,
    value: PlayerMovement(
      client_clock: 0x1234,
      commands: list.map(kinds(), fn(kind) { kind.command }),
    ),
    encode: player_movement.encode,
    decode: player_movement.decode,
  )
}

pub fn a_kind_of_30_or_31_is_refused_and_named_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([30, 31], fn(kind) {
    assert player_movement.decode(movement_body([#(kind, [u32(0)])]))
      == Error(bit_stream.UnexpectedValue(
        field: "movement_command",
        value: kind,
      ))
      as "0x1400af930: the client's reader fails a kind above 29, and the writer 0x1400af840 refuses it too"
  })
  assert player_movement.decode(
      movement_body([#(0, [u32(1)]), #(31, [u32(0)]), #(0, [u32(2)])]),
    )
    == Error(bit_stream.UnexpectedValue(field: "movement_command", value: 31))
    as "a kind of 31 after a good command refuses the whole message"
}

pub fn a_count_beyond_the_commands_the_body_holds_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let two = [#(0, [u32(1)]), #(0, [u32(2)])]
  let body = movement_body(two)
  assert player_movement.decode(set_count(body, 3))
    == Error(bit_stream.EndOfData)
    as "0x1400b06f0: the reader takes the count's commands one by one, so a third that the bytes do not hold fails the read"
  assert player_movement.decode(set_count(body, 0xFFFFFFFF))
    == Error(bit_stream.EndOfData)
    as "a count of billions fails where the bytes end"
  assert player_movement.decode(set_count(movement_body([]), 1))
    == Error(bit_stream.EndOfData)
    as "a count of 1 with no command"
}

/// The body with its 32-bit count (the second 32 bits) set to `count`.
fn set_count(body: BitArray, count: Int) -> BitArray {
  message_support.set_bits(body:, at: 32, width: 32, to: count)
}

// ---- test 4: kinds 8 and 11 are half floats ----

pub fn kinds_8_and_11_hold_half_floats_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    movement_body([
      #(8, [half(0x3C00), half(0xBC00), half(0x7C00), bit(0)]),
      #(11, [half(0x7C00), half(0x3C00), half(0xBC00), bit(1)]),
    ])
  let assert Ok(PlayerMovement(commands: [velocity, move_asked], ..)) =
    player_movement.decode(body)
    as "the two commands decode"
  let assert Velocity(MovementVelocity(x:, y:, z:, ..)) = velocity
    as "kind 8 is the velocity"
  assert [
      half_float.from_bits(x),
      half_float.from_bits(y),
      half_float.from_bits(z),
    ]
    == [Finite(1.0), Finite(-1.0), Infinite(negative: False)]
    as "0x1401c9800: 0x3c00 is 1.0, 0xbc00 is -1.0 and 0x7c00 is infinity"
  let assert MoveAsked(MovementMoveAsked(x:, y:, z:, ..)) = move_asked
    as "kind 11 is the move asked for"
  assert [
      half_float.from_bits(x),
      half_float.from_bits(y),
      half_float.from_bits(z),
    ]
    == [Infinite(negative: False), Finite(1.0), Finite(-1.0)]
    as "kind 11 holds half floats as kind 8 does"
}

// ---- the five small messages ----

pub fn zone_value_changed_is_two_values_of_15_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x63a: the old value and the new value, 15 bits each",
    body: packed([#(15, 0x1234), #(15, 0x7FFF)]),
    value: ZoneValueChanged(old_value: 0x1234, new_value: 0x7FFF),
    encode: zone_value_changed.encode,
    decode: zone_value_changed.decode,
  )
}

pub fn the_answer_to_0xf1_is_values_of_4_1_and_14_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0xd5: 4, 1 and 14 bits",
    body: packed([#(4, 0xA), #(1, 1), #(14, 0x2ABC)]),
    value: MovementSendIntervalAnswer(field_1: 0xA, field_2: 1, field_3: 0x2ABC),
    encode: movement_send_interval_answer.encode,
    decode: movement_send_interval_answer.decode,
  )
}

pub fn the_move_speed_setting_is_one_32_bit_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x63b: one 32-bit value",
    body: packed([u32(2)]),
    value: MoveSpeedSetting(move_speed: 2),
    encode: move_speed_setting.encode,
    decode: move_speed_setting.decode,
  )
}

pub fn the_fall_value_is_one_32_bit_float_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0xfb: one float of 32 bits, here 2.0",
    body: packed([u32(0x40000000)]),
    value: FallValue(field_1: 0x40000000),
    encode: fall_value.encode,
    decode: fall_value.decode,
  )
}

pub fn falling_below_the_floor_is_a_bit_and_the_camera_position_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0xfc: the no-ground bit, then three floats of 32 bits: 1.0, 2.0 and -3.0",
    body: packed([bit(1), u32(0x3F800000), u32(0x40000000), u32(0xC0400000)]),
    value: FellBelowFloor(
      no_ground: 1,
      camera_x: 0x3F800000,
      camera_y: 0x40000000,
      camera_z: 0xC0400000,
    ),
    encode: fell_below_floor.encode,
    decode: fell_below_floor.decode,
  )
}

pub fn the_client_message_module_reads_each_by_its_number_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(0x0637, movement_body([#(0, [u32(1)])])),
      #(0x063A, packed([#(15, 1), #(15, 2)])),
      #(0x00D5, packed([#(4, 1), #(1, 0), #(14, 3)])),
      #(0x063B, packed([u32(1)])),
      #(0x00FB, packed([u32(0)])),
      #(0x00FC, packed([bit(0), u32(0), u32(0), u32(0)])),
    ],
    fn(entry) {
      let #(id, body) = entry
      let assert Ok(message) = client_message.decode(message_id: id, body:)
        as "the number names a message the client sends"
      assert client_message.message_id(message) == id
        as "the message names its own number"
      assert client_message.encode(message) == Ok(body)
        as "and encodes back to the body"
    },
  )
}
