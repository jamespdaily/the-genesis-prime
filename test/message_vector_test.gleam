//// Each Milestone 1 message against the client's own bytes. A body vector is
//// the fact file's `vector.opcode.<id>.body` record, from the client's writer
//// or reader run on the p-code emulator, and the values are the ones the record
//// gives. For each: the bytes decode to those values, the values encode back to
//// the same bytes, and every shorter run of the bytes (so one that ends inside a
//// field) is a decode error, as the client's reader fails with 0x80070026
//// (ReadBitsSlow 0x140336d60, vector.opcode.0xf1.body and
//// vector.opcode.0x3db.body). The bodies of 0x244 and 0x38C have no emulator
//// vector; theirs come from the records `opcode.0x244`, `opcode.0x38c`,
//// `vector.opcode.0x7e0.frame` and the writer 0x14007e1c0.

import genesis_prime/message/bit_stream.{
  type DecodeError, type EncodeError, Endpoint,
}
import genesis_prime/message/character_select_start.{CharacterSelectStart}
import genesis_prime/message/client_wrapper.{ClientWrapper}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_request.{LoginRequest}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/pong.{Pong}
import genesis_prime/message/realm_entry.{RealmEntry}
import genesis_prime/message/realm_handoff.{RealmHandoff}
import genesis_prime/message/realm_list.{RealmList}
import genesis_prime/message/realm_select_start.{RealmSelectStart}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/text_group.{TextGroup}
import genesis_prime/message/world_message.{WorldMessage}
import gleam/bit_array
import gleam/int
import gleam/list
import message_support
import owned_test

fn assert_vector(
  name name: String,
  body body: BitArray,
  value value: a,
  encode encode: fn(a) -> Result(BitArray, EncodeError),
  decode decode: fn(BitArray) -> Result(a, DecodeError),
) -> Nil {
  assert decode(body) == Ok(value)
    as { name <> ": the bytes decode to the record's values" }
  assert encode(value) == Ok(body)
    as { name <> ": the values encode back to the same bytes" }
  let length = bit_array.byte_size(body)
  int.range(from: 0, to: length, with: Nil, run: fn(_, shorter) {
    let assert Ok(prefix) = bit_array.slice(body, 0, shorter)
      as "a prefix of the vector exists"
    assert decode(prefix) == Error(bit_stream.EndOfData)
      as {
        name
        <> ": the first "
        <> int.to_string(shorter)
        <> " of "
        <> int.to_string(length)
        <> " bytes end inside a field"
      }
  })
}

pub fn server_hello_is_the_clients_373_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x3.body",
    body: message_support.hex(
      "aa3e0000 44332211 88776655 ccbbaa99 0807060504030201 efbe 1f14332fc157d75f19e3c2a2826242228264442404",
    ),
    value: ServerHello(
      build: 16_042,
      field_2: 0x11223344,
      field_3: 0x55667788,
      field_4: 0x99AABBCC,
      field_5: 0x0102030405060708,
      field_6: 0xBEEF,
      field_7: 0x1F,
      message_table_checksum: 0x097998A0,
      field_9: 0xCAFEBABE,
      field_10: 0x1112131415161718,
      field_11: 0x21222324,
    ),
    encode: server_hello.encode,
    decode: server_hello.decode,
  )
}

pub fn login_request_is_the_clients_1168_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x592.body",
    body: message_support.hex(
      "aa3e0000 0102030405060708 0400 4a00 6900 6d00 0000 101112131415161718191a1b1c1d1e1f 202122232425262728292a2b2c2d2e2f 41000000 42000000 43000000 44000000 02 6100 04 6200 6300 00 51000000 52000000 53000000 54000000 55000000 60000000 02 6400 71000000 72000000 73000000 74000000 75000000 81000000 82000000 83000000 84000000 99000000",
    ),
    value: LoginRequest(
      build: 16_042,
      files_digest: 0x0807060504030201,
      account_name: "Jim",
      field_4: message_support.hex(
        "10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f",
      ),
      field_5: message_support.hex(
        "20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f",
      ),
      field_6: 0x41,
      field_7: 0x42,
      field_8: 0x43,
      field_9: 0x44,
      processor_manufacturer: "a",
      processor_name: "bc",
      processor_description: "",
      processor_family: 0x51,
      processor_level: 0x52,
      processor_revision: 0x53,
      processor_clock_speed: 0x54,
      processor_core_count: 0x55,
      memory_mebibytes: 0x60,
      video_adapter_description: "d",
      video_adapter_vendor_id: 0x71,
      video_adapter_device_id: 0x72,
      video_adapter_subsystem_id: 0x73,
      video_adapter_revision: 0x74,
      video_adapter_memory_mebibytes: 0x75,
      processor_architecture: 0x81,
      windows_version: 0x82,
      service_pack: 0x83,
      os_flags: 0x84,
      realm_data_center_id: 0x99,
    ),
    encode: login_request.encode,
    decode: login_request.decode,
  )
}

pub fn an_account_name_of_251_characters_cannot_be_in_a_login_request_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(long) = login_request.decode(login_request_body())
    as "the vector decodes"
  let too_long = LoginRequest(..long, account_name: string_of("x", 251))
  assert login_request.encode(too_long)
    == Error(bit_stream.TextTooLong("account_name", 251, 250))
    as "opcode.0x592 and vector.0x1400c2f70.counted_text: an account name over 250 characters makes the request fail to serialise and nothing is sent"
  let longest = LoginRequest(..long, account_name: string_of("x", 250))
  let assert Ok(bytes) = login_request.encode(longest)
    as "vector.0x1400c2f70.counted_text: 250 characters and a zero are written"
  assert login_request.decode(bytes) == Ok(longest)
    as "the 250 characters read back"
}

fn login_request_body() -> BitArray {
  message_support.hex(
    "aa3e0000 0102030405060708 0400 4a00 6900 6d00 0000 101112131415161718191a1b1c1d1e1f 202122232425262728292a2b2c2d2e2f 41000000 42000000 43000000 44000000 02 6100 04 6200 6300 00 51000000 52000000 53000000 54000000 55000000 60000000 02 6400 71000000 72000000 73000000 74000000 75000000 81000000 82000000 83000000 84000000 99000000",
  )
}

fn string_of(character: String, count: Int) -> String {
  list.repeat(character, count)
  |> list.fold("", fn(built, next) { built <> next })
}

pub fn login_accepted_is_one_32_bit_value_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x591.body",
    body: message_support.hex("01000000"),
    value: LoginAccepted(field_1: 1),
    encode: login_accepted.encode,
    decode: login_accepted.decode,
  )
}

pub fn game_server_handoff_is_the_clients_351_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x3db.body",
    body: message_support.hex(
      "0100007f c05d 0102030405060708090a0b0c0d0e0f10 88776655 0a 4e00 6500 7800 7500 7300 34120000 7bf36a",
    ),
    value: GameServerHandoff(
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      session_key: message_support.session_key(),
      field_3: 0x55667788,
      realm_name: "Nexus",
      field_5: 0x1234,
      field_6: 3,
      field_7: 0x1ABCDE,
    ),
    encode: game_server_handoff.encode,
    decode: game_server_handoff.decode,
  )
}

pub fn game_hello_reply_is_the_clients_312_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x58f.body",
    body: message_support.hex(
      "d4c3b2a1 0102030405060708090a0b0c0d0e0f10 0000000000000000 06 6a00 6900 6d00 03000000",
    ),
    value: GameHelloReply(
      field_1: 0xA1B2C3D4,
      session_key: message_support.session_key(),
      field_3: 0,
      account_name: "jim",
      field_5: 3,
    ),
    encode: game_hello_reply.encode,
    decode: game_hello_reply.decode,
  )
}

pub fn enter_world_is_a_15_bit_value_and_five_floats_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0xad.body",
    body: message_support.hex("34120000c01f00001060004064210000000000003020"),
    value: EnterWorld(
      world_id: 0x1234,
      position_x: 0x3F800000,
      position_y: 0xC0200000,
      position_z: 0x42C88000,
      field_5: 0,
      field_6: 0x40600000,
    ),
    encode: enter_world.encode,
    decode: enter_world.decode,
  )
}

pub fn movement_send_interval_is_the_clients_74_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0xf1.body",
    body: message_support.hex("e359d148acd207000000"),
    value: MovementSendInterval(
      field_1: 3,
      field_2: 0x12345678,
      field_3: 0xAB,
      interval_milliseconds: 500,
    ),
    encode: movement_send_interval.encode,
    decode: movement_send_interval.decode,
  )
}

pub fn realm_handoff_is_the_clients_352_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x7a1.body",
    body: message_support.hex(
      "99000000 0102030405060708090a0b0c0d0e0f10 0100007f c15d 159c00ca00f000ea00e600 68240000 7c6f5e",
    ),
    value: RealmHandoff(
      field_1: 0x99,
      session_key: message_support.session_key(),
      realm_server: Endpoint(address: 0x7F000001, port: 24_001),
      field_4: 1,
      realm_name: "Nexus",
      field_6: 0x1234,
      field_7: 2,
      field_8: 0x0BCDEF,
    ),
    encode: realm_handoff.encode,
    decode: realm_handoff.decode,
  )
}

pub fn realm_list_is_the_clients_734_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x761.body",
    body: message_support.hex(
      "1032547698badcfe 01000000 07000000 04 6200 6300 11110000 10000000 76 24240000 a0a1a2a3a4a5a6a7a8a9aaabacadaeaf ff7f0200008040180012121212121212121494941415959555000000c0cc0c0080800019008118c01800",
    ),
    value: RealmList(
      field_1: 0xFEDCBA9876543210,
      realms: [
        RealmEntry(
          realm_id: 7,
          name: "bc",
          note_text_id: 0x1111,
          flags: 0x10,
          pvp_type: 2,
          status: 5,
          population: 3,
          field_8: 0x2424,
          field_9: message_support.hex("a0a1a2a3a4a5a6a7a8a9aaabacadaeaf"),
          field_10: 0x3FFF,
          count: 9,
          last_played: "a",
          field_13: 0x4848484848484848,
          field_14: 0x5050,
          field_15: 0x5252,
          field_16: 0x5454,
          field_17: 0x5656,
        ),
      ],
      text_groups: [TextGroup(field_1: 0x3333, texts: ["d", "bc"])],
    ),
    encode: realm_list.encode,
    decode: realm_list.decode,
  )
}

pub fn a_realm_list_with_no_realms_and_no_groups_is_128_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x761.body (no realms, no groups)",
    body: message_support.hex("05000000 00000000 00000000 00000000"),
    value: RealmList(field_1: 5, realms: [], text_groups: []),
    encode: realm_list.encode,
    decode: realm_list.decode,
  )
}

pub fn character_select_start_has_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x7e0.frame (the frame is only its 6 header bytes)",
    body: <<>>,
    value: CharacterSelectStart,
    encode: character_select_start.encode,
    decode: character_select_start.decode,
  )
}

pub fn realm_select_start_has_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "opcode.0x7a4 (the frame is only the header 06 00 00 00 a4 07)",
    body: <<>>,
    value: RealmSelectStart,
    encode: realm_select_start.encode,
    decode: realm_select_start.decode,
  )
}

pub fn the_client_wrapper_body_is_the_inner_frame_with_its_length_in_the_clear_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "vector.opcode.0x7e0.frame: the inner frame of 0x244 is 06 00 00 00 03 89",
    body: message_support.hex("06 00 00 00 03 89"),
    value: ClientWrapper(inner_frame: message_support.hex("06 00 00 00 03 89")),
    encode: client_wrapper.encode,
    decode: client_wrapper.decode,
  )
}

pub fn the_world_message_body_is_a_5_bit_value_then_the_inner_frame_test() -> Nil {
  use <- owned_test.run(5000)
  assert_vector(
    name: "opcode.0x38c: the value 3 in 5 bits, then the inner frame 06 00 00 00 e0 07 from the next byte",
    body: message_support.hex("03 06 00 00 00 e0 07"),
    value: WorldMessage(
      field_1: 3,
      inner_frame: message_support.hex("06 00 00 00 e0 07"),
    ),
    encode: world_message.encode,
    decode: world_message.decode,
  )
}

pub fn a_body_with_a_whole_byte_after_its_last_field_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert login_accepted.decode(message_support.hex("01000000 00"))
    == Error(bit_stream.TrailingBytes(1))
    as "vector.opcode.0x591.body is 32 bits, a whole 4 bytes; a fifth byte is not part of any field"
  assert character_select_start.decode(<<0>>)
    == Error(bit_stream.TrailingBytes(1))
    as "vector.opcode.0x7e0.frame: the body is empty"
  assert movement_send_interval.decode(message_support.hex(
      "e359d148acd207000000 00",
    ))
    == Error(bit_stream.TrailingBytes(1))
    as "vector.opcode.0xf1.body is 74 bits in 10 bytes; an 11th byte is not padding"
}

pub fn pong_is_the_clients_8_bits_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#("00", 0), #("13", 19), #("14", 20), #("ff", 255)], fn(case_) {
    message_support.assert_vector(
      name: "vector.opcode.0x1.body, number " <> int.to_string(case_.1),
      body: message_support.hex(case_.0),
      value: Pong(sequence_number: case_.1),
      encode: pong.encode,
      decode: pong.decode,
    )
  })
}
