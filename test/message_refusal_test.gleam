//// A value wider than its field is refused when the message is encoded,
//// whichever message it is in (issue test 3). The client's own writers mask a
//// wide value to the field's low bits (vector.0x140336380.fields `(0xFF, 4)`
//// -> `0f`, and vector.opcode.0x3.body, where a 5-bit field given 0x3F writes
//// the same bytes as 0x1F), so a value that does not fit is a mistake the
//// server would otherwise hide. The widths are each field's in the schema.

import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/client_wrapper.{ClientWrapper}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_request.{LoginRequest}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/realm_entry.{RealmEntry}
import genesis_prime/message/realm_handoff.{RealmHandoff}
import genesis_prime/message/realm_list.{RealmList}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/text_group.{TextGroup}
import genesis_prime/message/world_message.{WorldMessage}
import gleam/list
import message_support
import owned_test

pub fn a_server_hello_field_wider_than_5_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let hello =
    ServerHello(
      build: 16_042,
      field_2: 0,
      field_3: 0,
      field_4: 0,
      field_5: 0,
      field_6: 0,
      field_7: 0x1F,
      message_table_checksum: 0x097998A0,
      field_9: 0,
      field_10: 0,
      field_11: 0,
    )
  assert server_hello.encode(ServerHello(..hello, field_7: 0x20))
    == Error(bit_stream.ValueDoesNotFit("field_7", 5, 0x20))
    as "vector.opcode.0x3.body: the 5-bit field holds up to 0x1F"
  assert server_hello.encode(ServerHello(..hello, build: 0x1_0000_0000))
    == Error(bit_stream.ValueDoesNotFit("build", 32, 0x1_0000_0000))
    as "ReadMessage0003Body 0x1400a9140: the build is 32 bits"
  assert server_hello.encode(ServerHello(..hello, field_10: -1))
    == Error(bit_stream.ValueDoesNotFit("field_10", 64, -1))
    as "the client's fields are unsigned"
}

pub fn a_login_request_with_a_wide_value_or_a_wrong_sized_key_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(request) =
    login_request.decode(message_support.hex(
      "aa3e0000 0102030405060708 0400 4a00 6900 6d00 0000 101112131415161718191a1b1c1d1e1f 202122232425262728292a2b2c2d2e2f 41000000 42000000 43000000 44000000 02 6100 04 6200 6300 00 51000000 52000000 53000000 54000000 55000000 60000000 02 6400 71000000 72000000 73000000 74000000 75000000 81000000 82000000 83000000 84000000 99000000",
    ))
    as "vector.opcode.0x592.body decodes"
  assert login_request.encode(
      LoginRequest(..request, realm_data_center_id: 0x1_0000_0000),
    )
    == Error(bit_stream.ValueDoesNotFit(
      "realm_data_center_id",
      32,
      0x1_0000_0000,
    ))
    as "WriteMessage0592Body 0x14007dd40 writes the data center id in 32 bits"
  assert login_request.encode(
      LoginRequest(..request, files_digest: 0x1_0000_0000_0000_0000),
    )
    == Error(bit_stream.ValueDoesNotFit(
      "files_digest",
      64,
      0x1_0000_0000_0000_0000,
    ))
    as "the digest is 64 bits"
  assert login_request.encode(LoginRequest(..request, field_4: <<1, 2, 3>>))
    == Error(bit_stream.WrongByteCount("field_4", 16, 3))
    as "WriteGuid 0x1400a8780: a GUID is 16 bytes"
}

pub fn a_login_accepted_value_wider_than_32_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert login_accepted.encode(LoginAccepted(field_1: 0x1_0000_0000))
    == Error(bit_stream.ValueDoesNotFit("field_1", 32, 0x1_0000_0000))
    as "ReadMessage0591Body 0x14007ab50: one 32-bit value"
}

pub fn a_game_server_handoff_with_a_wide_value_or_port_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let handoff =
    GameServerHandoff(
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      session_key: message_support.session_key(),
      field_3: 0,
      realm_name: "Nexus",
      field_5: 0,
      field_6: 3,
      field_7: 0x1ABCDE,
    )
  assert game_server_handoff.encode(GameServerHandoff(..handoff, field_6: 4))
    == Error(bit_stream.ValueDoesNotFit("field_6", 2, 4))
    as "ReadMessage03DBBody 0x14007d6a0: a 2-bit value"
  assert game_server_handoff.encode(
      GameServerHandoff(..handoff, field_7: 0x200000),
    )
    == Error(bit_stream.ValueDoesNotFit("field_7", 21, 0x200000))
    as "ReadMessage03DBBody 0x14007d6a0: a 21-bit value"
  assert game_server_handoff.encode(
      GameServerHandoff(
        ..handoff,
        game_server: Endpoint(address: 0x7F000001, port: 65_536),
      ),
    )
    == Error(bit_stream.ValueDoesNotFit("game_server", 16, 65_536))
    as "ReadIpv4Endpoint 0x1400a8980: the port is 16 bits"
  assert game_server_handoff.encode(
      GameServerHandoff(
        ..handoff,
        game_server: Endpoint(address: 0x1_0000_0000, port: 1),
      ),
    )
    == Error(bit_stream.ValueDoesNotFit("game_server", 32, 0x1_0000_0000))
    as "ReadIpv4Endpoint 0x1400a8980: the address is 32 bits"
}

pub fn a_game_hello_reply_with_a_wide_value_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let reply =
    GameHelloReply(
      field_1: 0xA1B2C3D4,
      session_key: message_support.session_key(),
      field_3: 0,
      account_name: "jim",
      field_5: 3,
    )
  assert game_hello_reply.encode(
      GameHelloReply(..reply, field_3: 0x1_0000_0000_0000_0000),
    )
    == Error(bit_stream.ValueDoesNotFit("field_3", 64, 0x1_0000_0000_0000_0000))
    as "WriteMessage058FBody 0x14007e320: a 64-bit value"
  assert game_hello_reply.encode(GameHelloReply(..reply, session_key: <<>>))
    == Error(bit_stream.WrongByteCount("session_key", 16, 0))
    as "opcode.0x58f: the session key is 16 bytes"
}

pub fn an_enter_world_value_wider_than_15_bits_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let world =
    EnterWorld(
      world_id: 0x1234,
      position_x: 0,
      position_y: 0,
      position_z: 0,
      field_5: 0,
      field_6: 0,
    )
  assert enter_world.encode(EnterWorld(..world, world_id: 0x8000))
    == Error(bit_stream.ValueDoesNotFit("world_id", 15, 0x8000))
    as "ReadMessage00ADBody 0x14007e9e0: a 15-bit value, the World id (opcode.0xad)"
  assert enter_world.encode(EnterWorld(..world, position_z: 0x1_0000_0000))
    == Error(bit_stream.ValueDoesNotFit("position_z", 32, 0x1_0000_0000))
    as "ReadFloat 0x14006c1c0: a float is 32 bits"
}

pub fn a_realm_list_with_a_wide_entry_value_or_too_many_texts_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let entry =
    RealmEntry(
      realm_id: 7,
      name: "bc",
      note_text_id: 0,
      flags: 0,
      pvp_type: 2,
      status: 5,
      population: 3,
      field_8: 0,
      field_9: message_support.hex("a0a1a2a3a4a5a6a7a8a9aaabacadaeaf"),
      field_10: 0x3FFF,
      count: 0,
      last_played: "",
      field_13: 0,
      field_14: 0,
      field_15: 0,
      field_16: 0,
      field_17: 0,
    )
  let list_of = fn(entry) {
    RealmList(field_1: 0, realms: [entry], text_groups: [])
  }
  assert realm_list.encode(list_of(RealmEntry(..entry, pvp_type: 4)))
    == Error(bit_stream.ValueDoesNotFit("pvp_type", 2, 4))
    as "ReadRealmListEntry 0x1400ac130: PvP type is 2 bits"
  assert realm_list.encode(list_of(RealmEntry(..entry, status: 8)))
    == Error(bit_stream.ValueDoesNotFit("status", 3, 8))
    as "ReadRealmListEntry 0x1400ac130: status is 3 bits"
  assert realm_list.encode(list_of(RealmEntry(..entry, field_10: 0x4000)))
    == Error(bit_stream.ValueDoesNotFit("field_10", 14, 0x4000))
    as "ReadRealmListEntry 0x1400ac130: a 14-bit value"
  assert realm_list.encode(list_of(RealmEntry(..entry, field_9: <<1>>)))
    == Error(bit_stream.WrongByteCount("field_9", 16, 1))
    as "ReadRealmListEntry 0x1400ac130: 16 raw bytes"
  let too_many =
    RealmList(field_1: 0, realms: [], text_groups: [
      TextGroup(field_1: 0, texts: list.repeat("a", 256)),
    ])
  assert realm_list.encode(too_many)
    == Error(bit_stream.ValueDoesNotFit("texts", 8, 256))
    as "ReadRealmListTextGroup 0x1400ac590: the text count is 8 bits"
}

pub fn a_realm_handoff_with_a_wide_value_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let handoff =
    RealmHandoff(
      field_1: 0x99,
      session_key: message_support.session_key(),
      realm_server: Endpoint(address: 0x7F000001, port: 24_001),
      field_4: 1,
      realm_name: "Nexus",
      field_6: 0x1234,
      field_7: 2,
      field_8: 0x0BCDEF,
    )
  assert realm_handoff.encode(RealmHandoff(..handoff, field_4: 2))
    == Error(bit_stream.ValueDoesNotFit("field_4", 1, 2))
    as "ReadMessage07A1Body 0x1400a2110: a 1-bit flag"
  assert realm_handoff.encode(RealmHandoff(..handoff, field_8: 0x200000))
    == Error(bit_stream.ValueDoesNotFit("field_8", 21, 0x200000))
    as "ReadMessage07A1Body 0x1400a2110: a 21-bit value"
}

pub fn a_movement_send_interval_with_a_wide_value_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let interval =
    MovementSendInterval(
      field_1: 3,
      field_2: 0,
      field_3: 0xAB,
      interval_milliseconds: 500,
    )
  assert movement_send_interval.encode(
      MovementSendInterval(..interval, field_1: 4),
    )
    == Error(bit_stream.ValueDoesNotFit("field_1", 2, 4))
    as "ReadMessage00F1Body 0x1400a37d0: a 2-bit value first"
  assert movement_send_interval.encode(
      MovementSendInterval(..interval, field_3: 0x100),
    )
    == Error(bit_stream.ValueDoesNotFit("field_3", 8, 0x100))
    as "ReadMessage00F1Body 0x1400a37d0: an 8-bit value third"
}

pub fn a_wrapper_whose_inner_frame_length_is_not_its_size_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_wrapper.encode(
      ClientWrapper(inner_frame: message_support.hex("09 00 00 00 03 89")),
    )
    == Error(bit_stream.InnerFrameDisagrees("inner_frame"))
    as "WriteWholeFrameBody 0x140079f30 copies from the frame to the end its first dword gives"
  assert world_message.encode(WorldMessage(
      field_1: 0x20,
      inner_frame: message_support.hex("06 00 00 00 e0 07"),
    ))
    == Error(bit_stream.ValueDoesNotFit("field_1", 5, 0x20))
    as "WriteMessage038CBody 0x14007e1c0 writes the value in 5 bits"
  assert world_message.encode(WorldMessage(
      field_1: 3,
      inner_frame: message_support.hex("09 00 00 00 e0 07"),
    ))
    == Error(bit_stream.InnerFrameDisagrees("inner_frame"))
    as "WriteMessage038CBody 0x14007e1c0 copies the inner frame by its length"
}
