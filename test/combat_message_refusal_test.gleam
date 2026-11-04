//// What the combat messages refuse, as the client's own reader or writer
//// does. A value the schema limits is refused when it is encoded and when it
//// is read, and a body cut inside a field is a decode error that ends the
//// connection. Each case starts from a vector `combat_message_vector_test`
//// checks against the layouts in the fact file, and changes one field.
//// - `opcode.0x19d`: an action set index above 3 and a bar slot above 47
////   refuse the whole message (HandleActionSet 0x1403b97a0).
//// - `movement_command.kind_4`: a speed below 0.00001 or a path type of 2 or 3
////   fails the command (0x140781300, 0x140783910). The speed is a half float:
////   the numbers around the limit are worked from the format, 167 and 168
////   times 2^-24, which are 9.954e-6 and 1.0014e-5.
//// - `0x140096970`: a ghost's race above 17 fails the create
////   (InitUnitFromCreate 0x140456960, case 0x17).
//// - `opcode.0x9a`, `opcode.0x801` and `opcode.0x15a`: the three messages the
////   client sends, cut anywhere, fail as the client's reader fails
////   (0x80070026), which the client message module reports as malformed.

import genesis_prime/message/action_set.{ActionSet}
import genesis_prime/message/action_shortcut.{ActionShortcut}
import genesis_prime/message/bit_stream
import genesis_prime/message/cancel_cast
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_result
import genesis_prime/message/choose_resurrection
import genesis_prime/message/client_message
import genesis_prime/message/movement_path
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_create_ghost.{UnitCreateGhost}
import genesis_prime/message/unit_movement.{UnitMovement}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import message_support
import owned_test

const action_set_bytes =
  "30 10 88 00 00 00 00 00 9b 16 00 00 11 78 01 00 00 c8 d3 02 00 00"

/// Where the second shortcut's bag index starts in the action set vector: the
/// header is 3 + 2 + 6 + 6 bits and a shortcut is 4 + 9 + 32 + 32, so the
/// second starts at bit 94 and its bag index 13 bits later.
const second_bag_index_bit = 107

const ghost_bytes =
  "02 10 00 00 17 c2 81 41 01 c1 80 40 40 26 a0 10 04 20 06 00 02 30 04 40 06 30 44 18 17 16 15 14 13 12 11 04 47 00 64 00 15 50 4e 4c 4a 48 46 44 42 02 9a 19 99 98 aa 00 00 00 00 00 00 08 01 00 38 30 0c 00 ad 45 0c 00 6c 3a c4 01 00 00 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 38 05 4e 01 00 00 00 00 00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00"

/// Where a ghost's race starts: the unit id (32), the type (6), the character
/// id (64), the realm (14) and 'Ab Cd' as a wide text (1 + 7 + 5 times 16).
const ghost_race_bit = 204

const straight_path_bytes =
  "01 20 00 00 00 ff 00 00 08 00 f0 0f 00 40 04 00 00 00 fc 01 00 00 00 02 00 00 02 02 00 00 04 02 00 00 05 02 00 00 06 02 48 02 00 00 00 00 00"

/// Where the path's speed starts in that vector: the unit id and time (64), two
/// bits and a count (7), the kind 0 command (5 + 32), the kind 4's kind and
/// point count (15) and two points (192); the path type follows its 16 bits.
const speed_bit = 315

const path_type_bit = 331

pub fn an_action_set_index_above_3_is_refused_when_encoded_and_when_read_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(set) = action_set.decode(message_support.hex(action_set_bytes))
    as "the vector reads"
  list.each([4, 5, 7], fn(index) {
    assert action_set.encode(ActionSet(..set, action_set_index: index))
      == Error(bit_stream.ValueAtOrAboveLimit(
        field: "action_set_index",
        limit: 4,
        value: index,
      ))
      as "opcode.0x19d: an index above 3 refuses the whole message"
    assert action_set.decode(message_support.set_bits(
        body: message_support.hex(action_set_bytes),
        at: 0,
        width: 3,
        to: index,
      ))
      == Error(bit_stream.UnexpectedValue(
        field: "action_set_index",
        value: index,
      ))
      as "the reader refuses it too"
  })
}

pub fn a_bar_slot_above_47_is_refused_and_47_is_taken_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(set) = action_set.decode(message_support.hex(action_set_bytes))
    as "the vector reads, its last slot being 47"
  let shortcut =
    ActionShortcut(
      shortcut_type: 4,
      location: 4,
      bag_index: 48,
      object_id: 23_148,
    )
  assert action_set.encode(ActionSet(..set, shortcuts: [shortcut]))
    == Error(bit_stream.ValueAtOrAboveLimit(
      field: "bag_index",
      limit: 48,
      value: 48,
    ))
    as "opcode.0x19d: a slot above 47 refuses the whole message"
  list.each([48, 49, 0xFFFF_FFFF], fn(slot) {
    assert action_set.decode(message_support.set_bits(
        body: message_support.hex(action_set_bytes),
        at: second_bag_index_bit,
        width: 32,
        to: slot,
      ))
      == Error(bit_stream.UnexpectedValue(field: "bag_index", value: slot))
      as "the reader refuses it too"
  })
  assert action_set.decode(message_support.set_bits(
      body: message_support.hex(action_set_bytes),
      at: second_bag_index_bit,
      width: 32,
      to: 47,
    ))
    == Ok(set)
    as "slot 47 is the last the client takes"
}

pub fn a_path_with_a_speed_below_0_00001_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(moved) =
    unit_movement.decode(message_support.hex(straight_path_bytes))
    as "the vector reads"
  let assert [time, relayed_movement.Path(path)] = moved.commands
    as "a kind 0 then a kind 4"
  // 0: zero. 0x00A7: 167 x 2^-24 = 9.954e-6, just below. 0x8000: negative
  // zero. 0xC900: -10. 0xFC00: the sign bit set.
  list.each([0, 0x00A7, 0x8000, 0xC900, 0xFC00], fn(speed) {
    assert unit_movement.encode(
        UnitMovement(..moved, commands: [
          time,
          relayed_movement.Path(movement_path.MovementPath(..path, speed:)),
        ]),
      )
      == Error(bit_stream.ValueBelowMinimum(
        field: "speed",
        minimum: 0.00001,
        value: speed,
      ))
      as "movement_command.kind_4: a speed below 0.00001 fails the command"
    assert unit_movement.decode(message_support.set_bits(
        body: message_support.hex(straight_path_bytes),
        at: speed_bit,
        width: 16,
        to: speed,
      ))
      == Error(bit_stream.UnexpectedValue(field: "speed", value: speed))
      as "the reader refuses it too"
  })
  list.each(
    [
      0x00A8,
      0x03FF,
      0x0400,
      0x3C00,
      0x4900,
      0x7BFF,
      0x7C00,
      0x7C01,
      0x7E00,
      0x7FFF,
    ],
    fn(speed) {
      let body =
        message_support.set_bits(
          body: message_support.hex(straight_path_bytes),
          at: speed_bit,
          width: 16,
          to: speed,
        )
      let assert Ok(read) = unit_movement.decode(body)
        as "a speed of at least 0.00001 is taken: the smallest half above it, a subnormal, a normal, 1.0, 10.0, the largest normal and the patterns of exponent 31, which the client's converter reads as the finite 65536.0 to 131008.0"
      assert unit_movement.encode(read) == Ok(body)
        as "and written back as read"
    },
  )
}

pub fn a_path_type_of_2_or_3_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(moved) =
    unit_movement.decode(message_support.hex(straight_path_bytes))
    as "the vector reads"
  let assert [time, relayed_movement.Path(path)] = moved.commands
    as "a kind 0 then a kind 4"
  list.each([2, 3], fn(path_type) {
    assert unit_movement.encode(
        UnitMovement(..moved, commands: [
          time,
          relayed_movement.Path(movement_path.MovementPath(..path, path_type:)),
        ]),
      )
      == Error(bit_stream.ValueAtOrAboveLimit(
        field: "path_type",
        limit: 2,
        value: path_type,
      ))
      as "movement_command.kind_4: a type other than 0 and 1 fails the command"
    assert unit_movement.decode(message_support.set_bits(
        body: message_support.hex(straight_path_bytes),
        at: path_type_bit,
        width: 2,
        to: path_type,
      ))
      == Error(bit_stream.UnexpectedValue(field: "path_type", value: path_type))
      as "the reader refuses it too"
  })
  list.each([0, 1], fn(path_type) {
    assert result.is_ok(
      unit_movement.decode(message_support.set_bits(
        body: message_support.hex(straight_path_bytes),
        at: path_type_bit,
        width: 2,
        to: path_type,
      )),
    )
      as "types 0 and 1 are the two the client takes"
  })
}

pub fn a_ghost_of_a_race_above_17_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(ghost) =
    unit_create_ghost.decode(message_support.hex(ghost_bytes))
    as "the vector reads, its race being 3"
  list.each([18, 19, 31], fn(race_id) {
    assert unit_create_ghost.encode(UnitCreateGhost(..ghost, race_id:))
      == Error(bit_stream.ValueAtOrAboveLimit(
        field: "race_id",
        limit: 18,
        value: race_id,
      ))
      as "0x140096970: the client reports a race above 17 and the create fails"
    assert unit_create_ghost.decode(message_support.set_bits(
        body: message_support.hex(ghost_bytes),
        at: ghost_race_bit,
        width: 5,
        to: race_id,
      ))
      == Error(bit_stream.UnexpectedValue(field: "race_id", value: race_id))
      as "the reader refuses it too"
  })
  assert unit_create_ghost.encode(UnitCreateGhost(..ghost, race_id: 17))
    == Ok(message_support.set_bits(
      body: message_support.hex(ghost_bytes),
      at: ghost_race_bit,
      width: 5,
      to: 17,
    ))
    as "race 17 is the last the client takes"
}

pub fn a_cut_press_cancel_or_resurrect_choice_is_malformed_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(0x9A, "03 28 00 80 02 00 45 23 01 00 01", "opcode.0x9a"),
      #(0x801, "04 28 00 80 06 02", "opcode.0x801"),
      #(0x15A, "01 10 00 00 02 00 00 00 00", "opcode.0x15a"),
    ],
    fn(message) {
      let #(message_id, hex, fact) = message
      let body = message_support.hex(hex)
      assert result.is_ok(client_message.decode(message_id:, body:))
        as { fact <> ": the whole body is the message" }
      let length = bit_array.byte_size(body)
      int.range(from: 0, to: length, with: Nil, run: fn(_, shorter) {
        let assert Ok(cut) = bit_array.slice(body, 0, shorter)
          as "a prefix of the body exists"
        assert client_message.decode(message_id:, body: cut)
          == Error(client_message.Malformed(
            message_id:,
            error: bit_stream.EndOfData,
          ))
          as {
            fact
            <> ": a body cut after "
            <> int.to_string(shorter)
            <> " of "
            <> int.to_string(length)
            <> " bytes fails as the client's reader does (0x80070026)"
          }
      })
    },
  )
}

pub fn a_whole_byte_after_a_press_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_message.decode(
      message_id: 0x9A,
      body: message_support.hex("03 28 00 80 02 00 45 23 01 00 01 00"),
    )
    == Error(client_message.Malformed(
      message_id: 0x9A,
      error: bit_stream.TrailingBytes(count: 1),
    ))
    as "a body longer than the message is not the message"
}

pub fn the_three_client_messages_are_taken_by_their_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_message.decode(
      message_id: 0x9A,
      body: message_support.hex("03 28 00 80 02 00 45 23 01 00 01"),
    )
    == Ok(
      client_message.CastAbility(cast_ability.CastAbility(
        client_cast_id: 0x80002803,
        bag_index: 2,
        target_unit_id: 0x12345,
        press: 1,
      )),
    )
    as "opcode.0x9a"
  assert client_message.decode(
      message_id: 0x801,
      body: message_support.hex("04 28 00 80 06 02"),
    )
    == Ok(
      client_message.CancelCast(cancel_cast.CancelCast(
        cast_id: 0x80002804,
        reason: cast_result.SpellCancelled,
        field_3: 1,
      )),
    )
    as "opcode.0x801"
  assert client_message.decode(
      message_id: 0x15A,
      body: message_support.hex("01 10 00 00 02 00 00 00 00"),
    )
    == Ok(
      client_message.ChooseResurrection(choose_resurrection.ChooseResurrection(
        unit_id: 0x1001,
        choice: 2,
        field_3: 0,
      )),
    )
    as "opcode.0x15a"
  assert client_message.decode(message_id: 0x9B, body: <<>>)
    == Error(client_message.UnknownMessage(message_id: 0x9B))
    as "opcode.0x9a: 0x9b, the ground-placed cast, is a message the schema does not hold"
}

pub fn a_path_with_a_value_or_last_bit_the_server_does_not_write_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  // The kind 4 record's 32-bit value starts after the mode, 4 bits after the
  // path type; the last bit follows it.
  let value_bit = path_type_bit + 2 + 4
  assert unit_movement.decode(message_support.set_bits(
      body: message_support.hex(straight_path_bytes),
      at: value_bit,
      width: 32,
      to: 77,
    ))
    == Error(bit_stream.UnexpectedValue(field: "value", value: 77))
    as "movement_command.kind_4: the value and the last bit are unread, so the server writes 0 and the codec takes no other"
  assert unit_movement.decode(message_support.set_bits(
      body: message_support.hex(straight_path_bytes),
      at: value_bit + 32,
      width: 1,
      to: 1,
    ))
    == Error(bit_stream.UnexpectedValue(field: "last_bit", value: 1))
    as "and the same for the last bit"
}
