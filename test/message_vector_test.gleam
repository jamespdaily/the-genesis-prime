//// Each Milestone 1 message against the client's own bytes. A body vector is
//// the fact file's `vector.opcode.<id>.body` record, from the client's writer
//// or reader run on the p-code emulator, and `assert_vector` reads the bytes
//// from that record's statement (it fails when the record is missing or gives
//// other bytes); the values are the ones the record gives. For each: the bytes
//// decode to those values, the values encode back to the same bytes, and every
//// shorter run of the bytes (so one that ends inside a field) is a decode
//// error, as the client's reader fails with 0x80070026 (ReadBitsSlow
//// 0x140336d60, vector.opcode.0xf1.body and vector.opcode.0x3db.body). The
//// body of 0x244 is the inner frame of `vector.opcode.0x7e0.frame`; the body of
//// 0x38C has no emulator vector, so its layout comes from `opcode.0x38c` and
//// its inner frame from `opcode.0x7e0`.

import fact_file
import genesis_prime/message/bit_stream.{Endpoint}
import genesis_prime/message/buyback_list.{BuybackList}
import genesis_prime/message/character_select_start.{CharacterSelectStart}
import genesis_prime/message/client_control_withdrawn.{ClientControlWithdrawn}
import genesis_prime/message/client_wrapper.{ClientWrapper}
import genesis_prime/message/enter_world.{EnterWorld}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/generic_error.{GenericError}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_refused.{LoginRefused}
import genesis_prime/message/login_request.{LoginRequest}
import genesis_prime/message/movement_send_interval.{MovementSendInterval}
import genesis_prime/message/pong.{Pong}
import genesis_prime/message/realm_entry.{RealmEntry}
import genesis_prime/message/realm_handoff.{RealmHandoff}
import genesis_prime/message/realm_list.{RealmList}
import genesis_prime/message/realm_select_start.{RealmSelectStart}
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/text_group.{TextGroup}
import genesis_prime/message/unit_dialog_open.{UnitDialogOpen}
import genesis_prime/message/vendor_item.{VendorItem}
import genesis_prime/message/vendor_items.{VendorItems}
import genesis_prime/message/vendor_price_slot.{VendorPriceSlot}
import genesis_prime/message/vendor_tab.{VendorTab}
import genesis_prime/message/world_loading_screen_shown.{WorldLoadingScreenShown}
import genesis_prime/message/world_message.{WorldMessage}
import gleam/list
import message_support
import owned_test

pub fn server_hello_is_the_clients_373_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x3.body",
    body: message_support.hex(
      "aa3e0000 44332211 88776655 ccbbaa99 0807060504030201 efbe 1f14332fc157d75f19e3c2a2826242228264442404",
    ),
    value: ServerHello(
      build: 16_042,
      realm_id: 0x11223344,
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
  message_support.assert_vector(
    name: "vector.opcode.0x592.body",
    body: message_support.hex(
      "aa3e0000 0102030405060708 0400 4a00 6900 6d00 0000 101112131415161718191a1b1c1d1e1f 202122232425262728292a2b2c2d2e2f 41000000 42000000 43000000 44000000 02 6100 04 6200 6300 00 51000000 52000000 53000000 54000000 55000000 60000000 02 6400 71000000 72000000 73000000 74000000 75000000 81000000 82000000 83000000 84000000 99000000",
    ),
    value: LoginRequest(
      build: 16_042,
      files_digest: 0x0807060504030201,
      account_name: "Jim",
      user_id: message_support.hex(
        "10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f",
      ),
      game_token: message_support.hex(
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
  message_support.assert_vector(
    name: "vector.opcode.0x591.body",
    body: message_support.hex("01000000"),
    value: LoginAccepted(disconnected_for_lag: 1),
    encode: login_accepted.encode,
    decode: login_accepted.decode,
  )
}

pub fn login_refused_is_the_clients_96_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x63d.body",
    body: message_support.hex("10000000 00000000 00000000"),
    value: LoginRefused(reason: 16, value: 0, field_3: 0),
    encode: login_refused.encode,
    decode: login_refused.decode,
  )
}

pub fn game_server_handoff_is_the_clients_351_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x3db.body",
    body: message_support.hex(
      "0100007f c05d 0102030405060708090a0b0c0d0e0f10 88776655 0a 4e00 6500 7800 7500 7300 34120000 7bf36a",
    ),
    value: GameServerHandoff(
      game_server: Endpoint(address: 0x7F000001, port: 24_000),
      session_key: message_support.session_key(),
      account_id: 0x55667788,
      realm_name: "Nexus",
      realm_flags: 0x1234,
      realm_pvp_type: 3,
      realm_note_text_id: 0x1ABCDE,
    ),
    encode: game_server_handoff.encode,
    decode: game_server_handoff.decode,
  )
}

pub fn game_hello_reply_is_the_clients_312_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
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
  message_support.assert_vector(
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
  message_support.assert_vector(
    name: "vector.opcode.0xf1.body",
    body: message_support.hex("e359d148acd207000000"),
    value: MovementSendInterval(
      world_difficulty: 3,
      world_prime_level: 0x12345678,
      world_flags: 0xAB,
      interval_milliseconds: 500,
    ),
    encode: movement_send_interval.encode,
    decode: movement_send_interval.decode,
  )
}

pub fn realm_handoff_is_the_clients_352_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
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
  message_support.assert_vector(
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
  message_support.assert_vector(
    name: "vector.opcode.0x761.body",
    body: message_support.hex("05000000 00000000 00000000 00000000"),
    value: RealmList(field_1: 5, realms: [], text_groups: []),
    encode: realm_list.encode,
    decode: realm_list.decode,
  )
}

pub fn character_select_start_has_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "opcode.0x7e0",
    body: <<>>,
    value: CharacterSelectStart,
    encode: character_select_start.encode,
    decode: character_select_start.decode,
  )
}

pub fn realm_select_start_has_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "opcode.0x7a4",
    body: <<>>,
    value: RealmSelectStart,
    encode: realm_select_start.encode,
    decode: realm_select_start.decode,
  )
}

pub fn the_loading_screen_message_is_0x83c_with_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert world_loading_screen_shown.message_id == 2108
    as "opcode.0x83c: registered at 0x14006e24a mov edx, 0x83c (2108)"
  message_support.assert_vector(
    name: "opcode.0x83c",
    body: <<>>,
    value: WorldLoadingScreenShown,
    encode: world_loading_screen_shown.encode,
    decode: world_loading_screen_shown.decode,
  )
}

pub fn the_control_withdrawn_message_is_0x639_with_an_empty_body_test() -> Nil {
  use <- owned_test.run(5000)
  assert client_control_withdrawn.message_id == 1593
    as "opcode.0x639: registered at 0x1400a86f1, the reader ReadEmptyBody (1593)"
  message_support.assert_vector(
    name: "opcode.0x639",
    body: <<>>,
    value: ClientControlWithdrawn,
    encode: client_control_withdrawn.encode,
    decode: client_control_withdrawn.decode,
  )
}

pub fn the_client_wrapper_body_is_the_inner_frame_with_its_length_in_the_clear_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_vector(
    name: "vector.opcode.0x7e0.frame",
    body: message_support.hex("06 00 00 00 03 89"),
    value: ClientWrapper(inner_frame: message_support.hex("06 00 00 00 03 89")),
    encode: client_wrapper.encode,
    decode: client_wrapper.decode,
  )
}

pub fn the_world_message_body_is_a_5_bit_value_then_the_inner_frame_test() -> Nil {
  use <- owned_test.run(5000)
  // The fact file has no vector for 0x38c: the record opcode.0x38c gives the
  // layout, the value 3 in 5 bits then the whole frame from the next byte, and
  // the record opcode.0x7e0 gives the frame of 0x7e0, which is the one inside.
  let inner_frame = message_support.hex("06 00 00 00 e0 07")
  assert fact_file.gives(record: "opcode.0x7e0", bytes: inner_frame) == Ok(Nil)
    as "opcode.0x7e0: the frame of message 0x7e0 is 06 00 00 00 e0 07"
  message_support.assert_codec(
    name: "opcode.0x38c",
    body: <<3, inner_frame:bits>>,
    value: WorldMessage(field_1: 3, inner_frame:),
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

pub fn unit_dialog_open_matches_client_layout_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x357: the client reads it with the reader it reads 0x355 with
  // (ReadUint32AndBitBody 0x14007c340), so vector.opcode.0x355.body's bytes are
  // its layout: the unit id, then one bit, 33 bits in all. Every shorter run of
  // them, the 32 bits of a unit id alone included, is a decode error.
  message_support.assert_vector(
    name: "vector.opcode.0x355.body",
    body: message_support.hex("0110000001"),
    value: UnitDialogOpen(unit_id: 0x1001, field_2: 1),
    encode: unit_dialog_open.encode,
    decode: unit_dialog_open.decode,
  )
  let assert Error(_) = unit_dialog_open.decode(message_support.hex("01100000"))
    as "opcode.0x357: a body of 32 bits is refused as too short"
  Nil
}

pub fn vendor_items_match_client_layout_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0x90b: the reader 0x140097ca0 reads the vendor's unit id (32 bits),
  // the tab count (32) and per tab two 32-bit values, the item count (32), the
  // items (0x140097ae0), the two multipliers as 32-bit floats and three bits.
  // 0x140097ae0 reads, in order, 32, 4, 32, 32, 32, 17, 32, 32, 32, 64 and 32
  // bits, then two slots of 3, 32 and 32 bits. The bytes are those widths laid
  // end to end, least significant bit first.
  let body =
    message_support.packed([
      #(32, 0x1001),
      #(32, 1),
      #(32, 3),
      #(32, 0x4000),
      #(32, 2),
      // item 1: a kind 0 item whose price the client computes
      #(32, 1),
      #(4, 0),
      #(32, 14_838),
      #(32, 0),
      #(32, 0),
      #(17, 0),
      #(32, 0),
      #(32, 0),
      #(32, 0),
      #(64, 0),
      #(32, 0),
      #(3, 0),
      #(32, 0),
      #(32, 0),
      #(3, 0),
      #(32, 0),
      #(32, 0),
      // item 2: every field distinct, both price slots of kind 2
      #(32, 2),
      #(4, 5),
      #(32, 0x1234),
      #(32, 6),
      #(32, 9),
      #(17, 0x1ABCD),
      #(32, 7),
      #(32, 3),
      #(32, 5),
      #(64, 0x0102030405060708),
      #(32, 0x99),
      #(3, 2),
      #(32, 104),
      #(32, 1),
      #(3, 2),
      #(32, 104),
      #(32, 1),
      #(32, 0x3F800000),
      #(32, 0x40000000),
      #(1, 1),
      #(1, 0),
      #(1, 1),
    ])
  let empty_slot = VendorPriceSlot(kind: 0, amount: 0, currency_id: 0)
  let priced_slot = VendorPriceSlot(kind: 2, amount: 104, currency_id: 1)
  message_support.assert_codec(
    name: "opcode.0x90b and 0x140097ae0: the reader's widths in order",
    body:,
    value: VendorItems(
      unit_id: 0x1001,
      tabs: [VendorTab(field_1: 3, field_2: 0x4000)],
      items: [
        VendorItem(
          unique_id: 1,
          kind: 0,
          entry_id: 14_838,
          currency_type_id: 0,
          stock_count: 0,
          prerequisite_id: 0,
          amount: 0,
          tab_id: 0,
          flags: 0,
          field_10: 0,
          field_11: 0,
          price_slot_1: empty_slot,
          price_slot_2: empty_slot,
        ),
        VendorItem(
          unique_id: 2,
          kind: 5,
          entry_id: 0x1234,
          currency_type_id: 6,
          stock_count: 9,
          prerequisite_id: 0x1ABCD,
          amount: 7,
          tab_id: 3,
          flags: 5,
          field_10: 0x0102030405060708,
          field_11: 0x99,
          price_slot_1: priced_slot,
          price_slot_2: priced_slot,
        ),
      ],
      buy_multiplier: 0x3F800000,
      sell_multiplier: 0x40000000,
      open: 1,
      full_list: 0,
      refuse: 1,
    ),
    encode: vendor_items.encode,
    decode: vendor_items.decode,
  )
}

pub fn buyback_list_and_generic_error_match_client_layout_test() -> Nil {
  use <- owned_test.run(5000)
  // opcode.0xbc: the reader 0x14008e560 reads a 32-bit count, then that many
  // entries, so an empty list is one 32-bit zero.
  message_support.assert_codec(
    name: "opcode.0xbc: a 32-bit count of 0",
    body: message_support.packed([#(32, 0)]),
    value: BuybackList(entries: []),
    encode: buyback_list.encode,
    decode: buyback_list.decode,
  )
  // opcode.0x106: the reader reads one 8-bit code.
  // 59 is the code of a unit the client does not show; 255 fills the eighth bit.
  list.each([59, 255], fn(code) {
    message_support.assert_codec(
      name: "opcode.0x106: an 8-bit code",
      body: message_support.packed([#(8, code)]),
      value: GenericError(code:),
      encode: generic_error.encode,
      decode: generic_error.decode,
    )
  })
}

pub fn pong_is_the_clients_8_bits_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#("00", 0), #("13", 19), #("14", 20), #("ff", 255)], fn(case_) {
    message_support.assert_vector(
      name: "vector.opcode.0x1.body",
      body: message_support.hex(case_.0),
      value: Pong(sequence_number: case_.1),
      encode: pong.encode,
      decode: pong.decode,
    )
  })
}
