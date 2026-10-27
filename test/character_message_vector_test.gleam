//// The messages of character select and entering the world against the
//// client's own bytes. A body vector is the fact file's `vector.opcode.<id>.body`
//// record, from the client's reader or writer run on the p-code emulator, and
//// the values are the ones the record gives. For each: the bytes decode to those
//// values, the values encode back to the same bytes, and every shorter run of
//// the bytes (one that ends inside a field) is a decode error, as the client's
//// reader fails with 0x80070026 (ReadBitsSlow 0x140336D60).
////
//// A float is kept as its bits in the codec, so each is written below as the
//// bits of the single-precision value the record names: 1.0 is 0x3F800000, 1.5
//// is 0x3FC00000, 2.0 is 0x40000000, 2.5 is 0x40200000, 3.5 is 0x40600000, 4.5
//// is 0x40900000, 5.5 is 0x40B00000, 0.25 is 0x3E800000 and -0.5 is
//// 0xBF000000 (IEEE 754 binary32).

import genesis_prime/message/bit_stream
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/character_list_entry.{CharacterListEntry}
import genesis_prime/message/choose_realm.{ChooseRealm}
import genesis_prime/message/client_control_echoed.{ClientControlEchoed}
import genesis_prime/message/client_control_granted.{ClientControlGranted}
import genesis_prime/message/create_character.{CreateCharacter}
import genesis_prime/message/create_character_carrier
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/delete_character.{DeleteCharacter}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/item_visual.{ItemVisual}
import genesis_prime/message/max_character_level.{MaxCharacterLevel}
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/rename_character.{RenameCharacter}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import gleam/int
import gleam/list
import message_support
import owned_test

pub fn the_character_list_is_the_clients_1372_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  message_support.assert_vector(
    name: "vector.opcode.0x117.body",
    body: message_support.hex(
      "0000000000f0d90101000000080706050403020104410062000d610a0000700000001000000020a0915801890700000100000083a2d119f0debc9a3803200254010000c03f0000204000006040000090400000b040ea0e00004002000000040000000600000008000000040000000000007f000000800000007d020000002200000004000000420000004400000032814c00e1c0a080604020004b00006000000080010000808b0b00e01408",
    ),
    value: CharacterList(
      server_time: 0x01D9F00000000000,
      characters: [
        CharacterListEntry(
          character_id: 0x0102030405060708,
          name: "Ab",
          gender: 1,
          race_id: 3,
          class_id: 2,
          faction_id: 166,
          level: 7,
          body_visuals: [
            ItemVisual(
              slot: 2,
              display_id: 0x1234,
              item_color_set_id: 0x56,
              dye: 0x789,
            ),
          ],
          worn_visuals: [
            ItemVisual(
              slot: 3,
              display_id: 0x2345,
              item_color_set_id: 0x67,
              dye: 0x89ABCDEF,
            ),
          ],
          world_id: 0x33,
          world_zone_id: 0x44,
          field_12: 0x55,
          position_x: 0x3FC00000,
          position_y: 0x40200000,
          position_z: 0x40600000,
          field_16: 0x40900000,
          field_17: 0x40B00000,
          path: 2,
          disabled: 1,
          requires_rename: 0,
          field_21: 0x77,
          customisation_labels: [1, 2],
          customisation_values: [3, 4],
          bone_values: [0x3F800000, 0x40000000],
          last_logged_out_days: 0x3E800000,
        ),
      ],
      enabled_creation_ids: [0x11],
      disabled_creation_ids: [0x21, 0x22],
      realm_id: 0x99,
      pending_removal_realm_id: 0x99,
      pending_removal_character_id: 0x0102030405060708,
      pending_removal_time: 600,
      reservations: 3,
      field_10: 12,
      field_11: 0x5C5C,
      faction_restriction: 167,
      free_level_50_available: 1,
    ),
    encode: character_list.encode,
    decode: character_list.decode,
  )
}

pub fn a_character_list_with_no_characters_and_empty_lists_is_395_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  message_support.assert_vector(
    name: "vector.opcode.0x117.body (no characters, empty lists)",
    body: message_support.hex(
      "0500000000000000000000000000000000000000990000000000000000000000000000000000000000000000000000000000",
    ),
    value: CharacterList(
      server_time: 5,
      characters: [],
      enabled_creation_ids: [],
      disabled_creation_ids: [],
      realm_id: 0x99,
      pending_removal_realm_id: 0,
      pending_removal_character_id: 0,
      pending_removal_time: 0,
      reservations: 0,
      field_10: 0,
      field_11: 0,
      faction_restriction: 0,
      free_level_50_available: 0,
    ),
    encode: character_list.encode,
    decode: character_list.decode,
  )
}

pub fn create_character_is_the_clients_379_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x25b.body",
    body: message_support.hex(
      "450000000a41006200200043006400120000000800000010000000180000002000000010000000000000fc010000f805",
    ),
    value: CreateCharacter(
      creation_id: 0x45,
      name: "Ab Cd",
      path: 2,
      customisation_labels: [1, 2],
      customisation_values: [3, 4],
      bone_values: [0x3F800000, 0xBF000000],
    ),
    encode: create_character.encode,
    decode: create_character.decode,
  )
}

pub fn create_character_with_no_customisation_or_bones_is_187_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x25b.body (no customisation, no bones)",
    body: message_support.hex(
      "070000000a41006200200043006400000000000000000000",
    ),
    value: CreateCharacter(
      creation_id: 7,
      name: "Ab Cd",
      path: 0,
      customisation_labels: [],
      customisation_values: [],
      bone_values: [],
    ),
    encode: create_character.encode,
    decode: create_character.decode,
  )
}

pub fn create_character_result_is_the_clients_102_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0xdc.body",
    body: message_support.hex("8877665544332211feca000003"),
    value: CreateCharacterResult(
      character_id: 0x1122334455667788,
      field_2: 0xCAFE,
      result: 3,
    ),
    encode: create_character_result.encode,
    decode: create_character_result.decode,
  )
}

pub fn play_character_is_one_64_bit_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x7dd.body",
    body: message_support.hex("0807060504030201"),
    value: PlayCharacter(character_id: 0x0102030405060708),
    encode: play_character.encode,
    decode: play_character.decode,
  )
}

pub fn delete_character_is_written_as_play_character_is_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x7dd.body (messages 0x7dd and 0x352 share one writer)",
    body: message_support.hex("0807060504030201"),
    value: DeleteCharacter(character_id: 0x0102030405060708),
    encode: delete_character.encode,
    decode: delete_character.decode,
  )
}

pub fn rename_character_is_the_clients_152_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x786.body",
    body: message_support.hex("08070605040302010a45006600200047006800"),
    value: RenameCharacter(character_id: 0x0102030405060708, name: "Ef Gh"),
    encode: rename_character.encode,
    decode: rename_character.decode,
  )
}

pub fn choose_realm_is_one_32_bit_realm_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x7df.body",
    body: message_support.hex("99000000"),
    value: ChooseRealm(realm_id: 0x99),
    encode: choose_realm.encode,
    decode: choose_realm.decode,
  )
}

pub fn delete_character_result_is_the_clients_38_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0xe6.body",
    body: message_support.hex("008d040000"),
    value: DeleteCharacterResult(result: 0, field_2: 0x1234),
    encode: delete_character_result.encode,
    decode: delete_character_result.decode,
  )
}

pub fn rename_character_result_is_the_clients_158_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x14b.body",
    body: message_support.hex("12c2814101c1804080c210001900084011801900"),
    value: RenameCharacterResult(
      result: 18,
      character_id: 0x0102030405060708,
      name: "Cd Ef",
    ),
    encode: rename_character_result.encode,
    decode: rename_character_result.decode,
  )
}

pub fn play_character_refused_is_one_3_bit_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x162.body",
    body: message_support.hex("05"),
    value: PlayCharacterRefused(field_1: 5),
    encode: play_character_refused.encode,
    decode: play_character_refused.decode,
  )
}

pub fn unit_is_player_is_two_32_bit_values_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x19b.body",
    body: message_support.hex("0110000002200000"),
    value: UnitIsPlayer(unit_id: 0x1001, field_2: 0x2002),
    encode: unit_is_player.encode,
    decode: unit_is_player.decode,
  )
}

pub fn player_entered_world_has_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x61.body",
    body: <<>>,
    value: PlayerEnteredWorld,
    encode: player_entered_world.encode,
    decode: player_entered_world.decode,
  )
}

pub fn terrain_loaded_is_the_clients_15_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0xf2.body",
    body: message_support.hex("3412"),
    value: TerrainLoaded(field_1: 0x1234),
    encode: terrain_loaded.encode,
    decode: terrain_loaded.decode,
  )
}

pub fn unit_destroyed_is_a_32_bit_unit_id_and_one_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x355.body",
    body: message_support.hex("0110000001"),
    value: UnitDestroyed(unit_id: 0x1001, field_2: 1),
    encode: unit_destroyed.encode,
    decode: unit_destroyed.decode,
  )
}

pub fn max_character_level_is_one_32_bit_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x591.body (message 0x36 is read by the same reader, 0x14007ab50)",
    body: message_support.hex("01000000"),
    value: MaxCharacterLevel(highest_level: 1),
    encode: max_character_level.encode,
    decode: max_character_level.decode,
  )
}

pub fn unit_create_player_is_the_clients_907_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  message_support.assert_vector(
    name: "vector.opcode.0x262.player",
    body: message_support.hex(
      "0110000014c2814101c180404026a010042006000230044006104418171615141312110121000000044700640015706e6c6a686664628220000080458501800012000000000000400300005003d800370000003838383838383838d3d2d2d2d2d2d2d2ca046208000080088022c008c01100",
    ),
    value: UnitCreatePlayer(
      unit_id: 0x1001,
      character_id: 0x0102030405060708,
      realm_id: 0x99,
      name: "Ab Cd",
      race_id: 1,
      class_id: 2,
      gender: 1,
      field_9: 0x1112131415161718,
      field_10: [0x21],
      field_11: "Gd",
      field_12: 5,
      field_13: [0x3132333435363738],
      field_14: [0x41],
      path: 3,
      field_16: 0x51,
      field_17: 0x61,
      field_18: 0x80,
      stats: [],
      server_time_estimate_start: 0x90,
      movement_commands: [],
      properties: [],
      item_visuals: [],
      field_25: 0xD0,
      faction_id: 0xD4,
      base_faction_id: 0xD8,
      field_28: 0xDC,
      field_29: 0xE0E0E0E0E0E0E0E0,
      field_31: 1,
      field_33: 0x5A5A5A5A5A5A5A5A,
      field_34: 0x99,
      field_36: 0x10C,
      field_37: 0x110,
      field_38: 0x114,
      field_39: 0x118,
      field_40: 0x11C,
    ),
    encode: unit_create_player.encode,
    decode: unit_create_player.decode,
  )
}

/// The player of `vector.opcode.0x262.position`: unit 1, character 1, realm 1,
/// "Ab", race 1, class 1, gender 0, every other value 0 and every other list
/// empty, with the one movement command the vector names.
fn minimal_player() -> UnitCreatePlayer {
  UnitCreatePlayer(
    unit_id: 1,
    character_id: 1,
    realm_id: 1,
    name: "Ab",
    race_id: 1,
    class_id: 1,
    gender: 0,
    field_9: 0,
    field_10: [],
    field_11: "",
    field_12: 0,
    field_13: [],
    field_14: [],
    path: 0,
    field_16: 0,
    field_17: 0,
    field_18: 0,
    stats: [],
    server_time_estimate_start: 0,
    movement_commands: [
      UnitPositionCommand(
        x: 0x45879585,
        y: 0xC487D70A,
        z: 0xC570E87B,
        blends: 0,
      ),
    ],
    properties: [],
    item_visuals: [],
    field_25: 0,
    faction_id: 0,
    base_faction_id: 0,
    field_28: 0,
    field_29: 0,
    field_31: 0,
    field_33: 0,
    field_34: 0,
    field_36: 0,
    field_37: 0,
    field_38: 0,
    field_39: 0,
    field_40: 0,
  )
}

pub fn a_player_with_a_position_command_is_the_clients_801_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  message_support.assert_vector(
    name: "vector.opcode.0x262.position (kind 2 at 4338.69, -1086.72, -3854.53, bit 0; the floats are 0x45879585, 0xC487D70A and 0xC570E87B)",
    body: message_support.hex(
      "01000000540000000000000040004010042006100200000000000000000000000000000000000000002088c2cac32285eb43e23d74b86200000000000000000000000000000000000000000000800000000000000000008000000000000000000000000000",
    ),
    value: minimal_player(),
    encode: unit_create_player.encode,
    decode: unit_create_player.decode,
  )
}

pub fn a_player_with_health_and_base_health_is_the_clients_912_bits_test() -> Nil {
  use <- owned_test.run(10_000)
  message_support.assert_vector(
    name: "vector.opcode.0x262.health (stat 0 is 136; property 7 is 136.0 twice, 0x43080000)",
    body: message_support.hex(
      "01000000540000000000000040004010042006100200000000000000000000000000000000018008000000000000104461e56191c2f521f11e3a5cb1800300008421000084210000000000000000000000000000000000000000004000000000000000000040000000000000000000000000",
    ),
    value: UnitCreatePlayer(
      ..minimal_player(),
      stats: [UnitStat(stat_id: 0, value: 136)],
      properties: [
        UnitProperty(property_id: 7, field_2: 0x43080000, value: 0x43080000),
      ],
    ),
    encode: unit_create_player.encode,
    decode: unit_create_player.decode,
  )
}

pub fn client_control_granted_is_a_value_a_bit_and_a_unit_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x636.body (the value in bits 0 to 31, the reset bit at 32, the unit id in bits 33 to 64)",
    body: message_support.hex("000000000300000000"),
    value: ClientControlGranted(echo_value: 0, reset_movement: 1, unit_id: 1),
    encode: client_control_granted.encode,
    decode: client_control_granted.decode,
  )
}

pub fn client_control_echoed_is_one_32_bit_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x635.body (the client's writer 0x14007d010 on the value 0)",
    body: message_support.hex("00000000"),
    value: ClientControlEchoed(echo_value: 0),
    encode: client_control_echoed.encode,
    decode: client_control_echoed.decode,
  )
}

pub fn the_control_messages_hold_the_clients_message_numbers_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_control_granted.message_id == 0x0636
    as "opcode.0x636: registered at 0x1400a8690 mov edx, 0x636"
  assert client_control_echoed.message_id == 0x0635
    as "opcode.0x635: registered at 0x1400a86c4 mov edx, 0x635"
}

pub fn a_unit_create_of_another_type_than_a_player_is_not_decoded_test() -> Nil {
  use <- owned_test.run(5000)
  assert unit_create_player.decode(message_support.hex("0110000025"))
    == Error(bit_stream.UnexpectedValue("unit_type", 37))
    as "vector.opcode.0x262.player: a type of 37 (0110000025) fails the client's reader; the server decodes only type 20, the player"
  assert unit_create_player.decode(message_support.hex("0110000001"))
    == Error(bit_stream.UnexpectedValue("unit_type", 1))
    as "opcode.0x262: only the type 20 has its data decoded here, so type 1 is refused"
}

pub fn a_first_tag_of_2_in_a_unit_create_is_not_decoded_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    message_support.hex(
      "0110000014c2814101c180404026a010042006000230044006104418171615141312110121000000044700640015706e6c6a686664628220000080458501800012000000000000400300005003d800370000003838383838383838d3d2d2d2d2d2d2d2ca046208000080088022c008c01100",
    )
  // The first of the three tagged values starts at bit 726 of the 907: the
  // 496 bits up to the player's data's end (vector.opcode.0x262.player), then
  // the 8-bit value, the 5-bit empty list, the 32-bit value, the 5-bit and
  // 8-bit and 7-bit and 9-bit empty lists and the five values of 32, 14, 14,
  // 32 and 64 bits.
  let tagged = message_support.set_bits(body:, at: 726, width: 2, to: 2)
  assert unit_create_player.decode(tagged)
    == Error(bit_stream.UnexpectedValue("first_tag", 2))
    as "vector.opcode.0x262.player: a first tag of 2 fails the client's reader"
}

pub fn a_unit_create_names_the_items_a_player_wears_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(player) =
    unit_create_player.decode(message_support.hex(
      "0110000014c2814101c180404026a010042006000230044006104418171615141312110121000000044700640015706e6c6a686664628220000080458501800012000000000000400300005003d800370000003838383838383838d3d2d2d2d2d2d2d2ca046208000080088022c008c01100",
    ))
    as "vector.opcode.0x262.player decodes"
  let worn =
    UnitCreatePlayer(..player, item_visuals: [
      ItemVisual(slot: 2, display_id: 0x1234, item_color_set_id: 0x56, dye: 7),
    ])
  let assert Ok(bytes) = unit_create_player.encode(worn)
    as "a unit with an item visual encodes"
  assert unit_create_player.decode(bytes) == Ok(worn)
    as "opcode.0x262: a count of 7 bits and that many item visuals (ReadItemVisual 0x1400AB890)"
}

pub fn a_body_with_a_whole_byte_after_its_last_field_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert delete_character_result.decode(message_support.hex("008d040000 00"))
    == Error(bit_stream.TrailingBytes(1))
    as "vector.opcode.0xe6.body is 38 bits in 5 bytes; a sixth byte is not part of any field"
  assert player_entered_world.decode(message_support.hex("00"))
    == Error(bit_stream.TrailingBytes(1))
    as "vector.opcode.0x61.body: no bytes"
  assert character_list.decode(message_support.hex(
      "0500000000000000000000000000000000000000990000000000000000000000000000000000000000000000000000000000 00",
    ))
    == Error(bit_stream.TrailingBytes(1))
    as "vector.opcode.0x117.body (no characters) is 395 bits in 50 bytes; a 51st byte is not padding"
}

pub fn each_message_module_holds_the_clients_message_number_test() -> Nil {
  use <- owned_test.run(5000)
  assert character_list.message_id == 0x0117
    as "opcode.0x117: registered at 0x14006da4e mov edx, 0x117"
  assert create_character.message_id == 0x025B
    as "opcode.0x25b: registered at 0x14006d987 mov edx, 0x25b"
  assert create_character_carrier.message_id == 0x025C
    as "opcode.0x25c: registered at 0x14006d638 mov edx, 0x25c"
  assert create_character_result.message_id == 0x00DC
    as "opcode.0xdc: registered at 0x14006dae1 mov edx, 0xdc"
  assert play_character.message_id == 0x07DD
    as "opcode.0x7dd: registered at 0x14006d5fc mov edx, 0x7dd"
  assert play_character_refused.message_id == 0x0162
    as "opcode.0x162: registered at 0x14006db12 mov edx, 0x162"
  assert delete_character.message_id == 0x0352
    as "opcode.0x352: registered at 0x14006d6a6 mov edx, 0x352"
  assert delete_character_result.message_id == 0x00E6
    as "opcode.0xe6: registered at 0x14006da7f mov edx, 0xe6"
  assert rename_character.message_id == 0x0786
    as "opcode.0x786: registered at 0x14006d714 mov edx, 0x786"
  assert rename_character_result.message_id == 0x014B
    as "opcode.0x14b: registered at 0x14006dc0d mov edx, 0x14b"
  assert max_character_level.message_id == 0x0036
    as "opcode.0x36: registered at 0x1400782c1 lea edx, [r9+0x36]"
  assert choose_realm.message_id == 0x07DF
    as "opcode.0x7df: registered at 0x14006d7bc mov edx, 0x7df"
  assert unit_create_player.message_id == 0x0262
    as "opcode.0x262: registered at 0x140074aea mov edx, 0x262"
  assert unit_is_player.message_id == 0x019B
    as "opcode.0x19b: registered at 0x140071973 mov edx, 0x19b"
  assert terrain_loaded.message_id == 0x00F2
    as "opcode.0xf2: registered at 0x140070fc6 mov edx, 0xf2"
  assert player_entered_world.message_id == 0x0061
    as "opcode.0x61: registered at 0x140071ac4 lea edx, [r9+0x61]"
  assert unit_destroyed.message_id == 0x0355
    as "opcode.0x355: registered at 0x140074b21 mov edx, 0x355"
  assert disconnect_notice.message_id == 0x036A
    as "opcode.0x36a: registered at 0x14006d889 mov edx, 0x36a"
}

pub fn a_disconnect_notice_is_one_5_bit_reason_test() -> Nil {
  use <- owned_test.run(5000)
  assert disconnect_notice.encode(DisconnectNotice(reason: 0x1F))
    == Ok(message_support.hex("1f"))
    as "opcode.0x36a: the reader reads 5 bits (0x14007e95e mov r8d, 0x5); vector.0x140336380.fields: a 5-bit 0x1F is the byte 1f"
  assert disconnect_notice.decode(message_support.hex("14"))
    == Ok(DisconnectNotice(reason: 20))
    as "opcode.0x36a: reason 20 has its own text"
  assert disconnect_notice.encode(DisconnectNotice(reason: 32))
    == Error(bit_stream.ValueDoesNotFit("reason", 5, 32))
    as "opcode.0x36a: a reason is 5 bits"
}

pub fn disconnect_notice_is_the_clients_5_bits_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#("06", 6), #("13", 19), #("14", 20), #("1f", 31)], fn(case_) {
    message_support.assert_vector(
      name: "vector.opcode.0x36a.body, reason " <> int.to_string(case_.1),
      body: message_support.hex(case_.0),
      value: DisconnectNotice(reason: case_.1),
      encode: disconnect_notice.encode,
      decode: disconnect_notice.decode,
    )
  })
}
