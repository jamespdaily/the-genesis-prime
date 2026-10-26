//// Each message the server sends in character select and while the player
//// enters the world is encoded under its own number, as the body of the
//// message's own codec. The numbers and bodies are those of the vectors in
//// `character_message_vector_test`.

import genesis_prime/character/server_message.{
  CharacterListed, CreateResult, DeleteResult, MovementIntervalSet, PlayRefused,
  PlayerEntered, PlayerUnitSet, RenameResult, UnitCreated, WorldEntered,
}
import genesis_prime/message/character_list.{CharacterList}
import genesis_prime/message/create_character_result.{CreateCharacterResult}
import genesis_prime/message/delete_character_result.{DeleteCharacterResult}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/play_character_refused.{PlayCharacterRefused}
import genesis_prime/message/player_entered_world.{PlayerEnteredWorld}
import genesis_prime/message/rename_character_result.{RenameCharacterResult}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_is_player.{UnitIsPlayer}
import message_support
import owned_test

pub fn a_create_result_is_message_0xdc_with_the_vectors_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_message.encode(
      CreateResult(CreateCharacterResult(
        character_id: 0x1122334455667788,
        field_2: 0xCAFE,
        result: 3,
      )),
    )
    == Ok(#(0x00DC, message_support.hex("8877665544332211feca000003")))
    as "opcode.0xdc and vector.opcode.0xdc.body"
}

pub fn a_rename_result_is_message_0x14b_with_the_vectors_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_message.encode(
      RenameResult(RenameCharacterResult(
        result: 18,
        character_id: 0x0102030405060708,
        name: "Cd Ef",
      )),
    )
    == Ok(#(
      0x014B,
      message_support.hex("12c2814101c1804080c210001900084011801900"),
    ))
    as "opcode.0x14b and vector.opcode.0x14b.body"
}

pub fn a_delete_result_is_message_0xe6_with_the_vectors_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_message.encode(
      DeleteResult(DeleteCharacterResult(result: 0, field_2: 0x1234)),
    )
    == Ok(#(0x00E6, message_support.hex("008d040000")))
    as "opcode.0xe6 and vector.opcode.0xe6.body"
}

pub fn a_refusal_to_play_is_message_0x162_with_the_vectors_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_message.encode(PlayRefused(PlayCharacterRefused(field_1: 5)))
    == Ok(#(0x0162, message_support.hex("05")))
    as "opcode.0x162 and vector.opcode.0x162.body"
}

pub fn the_world_messages_are_the_clients_numbers_with_the_vectors_bodies_test() -> Nil {
  use <- owned_test.run(5000)
  assert server_message.encode(
      WorldEntered(EnterWorld(
        world_id: 0x1234,
        position_x: 0x3F800000,
        position_y: 0xC0200000,
        position_z: 0x42C88000,
        field_5: 0,
        field_6: 0x40600000,
      )),
    )
    == Ok(#(
      0x00AD,
      message_support.hex("34120000c01f00001060004064210000000000003020"),
    ))
    as "opcode.0xad and vector.opcode.0xad.body"
  assert server_message.encode(
      PlayerUnitSet(UnitIsPlayer(unit_id: 0x1001, field_2: 0x2002)),
    )
    == Ok(#(0x019B, message_support.hex("0110000002200000")))
    as "opcode.0x19b and vector.opcode.0x19b.body"
  assert server_message.encode(
      MovementIntervalSet(MovementSendInterval(
        field_1: 3,
        field_2: 0x12345678,
        field_3: 0xAB,
        interval_milliseconds: 500,
      )),
    )
    == Ok(#(0x00F1, message_support.hex("e359d148acd207000000")))
    as "opcode.0xf1 and vector.opcode.0xf1.body"
  assert server_message.encode(PlayerEntered(PlayerEnteredWorld))
    == Ok(#(0x0061, <<>>))
    as "opcode.0x61 and vector.opcode.0x61.body"
}

pub fn a_character_list_is_message_0x117_with_the_vectors_body_test() -> Nil {
  use <- owned_test.run(5000)
  let empty =
    CharacterList(
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
    )
  assert server_message.encode(CharacterListed(empty))
    == Ok(#(
      0x0117,
      message_support.hex(
        "0500000000000000000000000000000000000000990000000000000000000000000000000000000000000000000000000000",
      ),
    ))
    as "opcode.0x117 and vector.opcode.0x117.body (no characters)"
}

pub fn a_unit_create_is_message_0x262_with_the_vectors_body_test() -> Nil {
  use <- owned_test.run(5000)
  let body =
    message_support.hex(
      "0110000014c2814101c180404026a010042006000230044006104418171615141312110121000000044700640015706e6c6a686664628220000080458501800012000000000000400300005003d800370000003838383838383838d3d2d2d2d2d2d2d2ca046208000080088022c008c01100",
    )
  let assert Ok(player) = unit_create_player.decode(body)
    as "vector.opcode.0x262.player decodes"
  assert server_message.encode(UnitCreated(player)) == Ok(#(0x0262, body))
    as "opcode.0x262 and vector.opcode.0x262.player"
}
