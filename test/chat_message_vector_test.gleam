//// The chat messages against bytes packed by hand from the layouts in the fact
//// file: `opcode.0x1c3`, `opcode.0x1d4`, `opcode.0x1c2`, `opcode.0x1c8`,
//// `opcode.0x1d3`, `opcode.0x1d9`, `opcode.0x1bc` and `opcode.0x1da`, with a
//// chat format as `0x140085ca0` reads it and a wide text as
//// `vector.0x140336040.wide_text` writes it ('Ab' is 04 41 00 62 00). Each
//// vector was packed by a script that follows the bit stream's rule, the least
//// significant bit of the first byte first, field by field with the widths
//// the facts give, and shares no code with the codec; the values are the ones
//// named beside each vector. The bytes decode to the values, the values encode
//// back to them, and every shorter run of the bytes ends inside a field.

import genesis_prime/message/bit_stream
import genesis_prime/message/chat_channel_joined.{ChatChannelJoined}
import genesis_prime/message/chat_channel_result
import genesis_prime/message/chat_format.{
  ArticleId, FilterMask, ItemGuid, ItemId, ItemRecord, Kind0, Kind1, Kind11,
  Kind2, Kind3, NavigationPoint, QuestId,
}
import genesis_prime/message/chat_format_article_id.{ChatFormatArticleId}
import genesis_prime/message/chat_format_filter_mask.{ChatFormatFilterMask}
import genesis_prime/message/chat_format_item_guid.{ChatFormatItemGuid}
import genesis_prime/message/chat_format_item_id.{ChatFormatItemId}
import genesis_prime/message/chat_format_item_record.{ChatFormatItemRecord}
import genesis_prime/message/chat_format_kind_0.{ChatFormatKind0}
import genesis_prime/message/chat_format_kind_1.{ChatFormatKind1}
import genesis_prime/message/chat_format_kind_11.{ChatFormatKind11}
import genesis_prime/message/chat_format_kind_2.{ChatFormatKind2}
import genesis_prime/message/chat_format_kind_3.{ChatFormatKind3}
import genesis_prime/message/chat_format_navigation_point.{
  ChatFormatNavigationPoint,
}
import genesis_prime/message/chat_format_quest_id.{ChatFormatQuestId}
import genesis_prime/message/chat_line.{ChatLine}
import genesis_prime/message/chat_line_accepted.{ChatLineAccepted}
import genesis_prime/message/chat_result.{ChatResult}
import genesis_prime/message/chat_zone_named.{ChatZoneNamed}
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/message/send_whisper.{SendWhisper}
import genesis_prime/message/whisper_failed.{WhisperFailed}
import gleam/list
import gleam/string
import message_support
import owned_test

pub fn the_message_numbers_are_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert send_chat_line.message_id == 451 as "opcode.0x1c3: message 0x1c3 (451)"
  assert send_whisper.message_id == 468 as "opcode.0x1d4: message 0x1d4 (468)"
  assert chat_line_accepted.message_id == 450
    as "opcode.0x1c2: message 0x1c2 (450)"
  assert chat_line.message_id == 456 as "opcode.0x1c8: message 0x1c8 (456)"
  assert chat_result.message_id == 467 as "opcode.0x1d3: message 0x1d3 (467)"
  assert whisper_failed.message_id == 473 as "opcode.0x1d9: message 0x1d9 (473)"
  assert chat_channel_joined.message_id == 444
    as "opcode.0x1bc: message 0x1bc (444)"
  assert chat_zone_named.message_id == 474
    as "opcode.0x1da: message 0x1da (474)"
}

pub fn a_say_line_is_a_type_an_id_a_text_no_formats_and_a_slot_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1c3: type 4 in 14 bits, id 0 in 64, 'Hi', 0 formats in 5, slot 1 in 16",
    body: message_support.hex(
      "04 00 00 00 00 00 00 00 00 00 01 12 40 1a 00 08 00 00",
    ),
    value: SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("Hi"),
      formats: [],
      chat_message_id: 1,
    ),
    encode: send_chat_line.encode,
    decode: send_chat_line.decode,
  )
}

pub fn a_zone_line_names_the_channel_id_the_server_gave_and_holds_an_item_link_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1c3 and 0x140085ca0: type 9 and id 0x123456789A, 'Link', one format of type 9 over 0 to 4 with the item GUID 0x0123456789ABCDEF, slot 0xFFFF",
    body: message_support.hex(
      "09 80 26 9e 15 8d 04 00 00 00 02 13 40 1a 80 1b c0 1a 40 48 00 00 02 80 f7 e6 d5 c4 b3 a2 91 80 ff 7f",
    ),
    value: SendChatLine(
      channel_type: 9,
      channel_id: 0x123456789A,
      text: bit_stream.utf16_units("Link"),
      formats: [
        ItemGuid(ChatFormatItemGuid(
          start: 0,
          end: 4,
          item_guid: 0x0123456789ABCDEF,
        )),
      ],
      chat_message_id: 0xFFFF,
    ),
    encode: send_chat_line.encode,
    decode: send_chat_line.decode,
  )
}

pub fn every_format_type_the_clients_reader_takes_has_its_own_data_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "0x140085ca0: type in 4 bits, start and end in 16 each, then types 0, 2, 3 one bit; 1, 7, 11 32 bits; 4 18 bits; 5 15 bits; 6 14 bits; 9 64 bits; 10 a 14-bit zone and two floats",
    body: message_support.hex(
      "04 00 00 00 00 00 00 00 00 80 41 18 80 18 c0 18 c0 82 00 00 01 80 21 00 30 00 40 3d 2c 1b 2a 03 00 04 00 86 00 a0 00 20 15 00 18 00 34 af 5a 06 00 07 00 34 12 3b 00 40 00 18 09 0e 01 20 01 40 b5 4a b5 2a 13 00 14 00 de 9b 57 13 cf 8a 46 02 54 01 60 01 80 57 03 00 00 fc 01 00 00 00 da 05 00 06 80 77 5f 00 80 03 00",
    ),
    value: SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("abc"),
      formats: [
        Kind0(ChatFormatKind0(start: 1, end: 2, field_4: 1)),
        Kind1(ChatFormatKind1(start: 2, end: 3, field_4: 0xA1B2C3D4)),
        Kind2(ChatFormatKind2(start: 3, end: 4, field_4: 0)),
        Kind3(ChatFormatKind3(start: 4, end: 5, field_4: 1)),
        ItemId(ChatFormatItemId(start: 5, end: 6, item_id: 0x2ABCD)),
        QuestId(ChatFormatQuestId(start: 6, end: 7, quest_id: 0x1234)),
        ArticleId(ChatFormatArticleId(start: 7, end: 8, article_id: 0x0123)),
        FilterMask(ChatFormatFilterMask(start: 8, end: 9, seed: 0x55AA55AA)),
        ItemGuid(ChatFormatItemGuid(
          start: 9,
          end: 10,
          item_guid: 0x0123456789ABCDEF,
        )),
        NavigationPoint(ChatFormatNavigationPoint(
          start: 10,
          end: 11,
          zone_id: 0x1ABC,
          x: 0x3F800000,
          y: 0x40000000,
        )),
        Kind11(ChatFormatKind11(start: 11, end: 12, field_4: 0xBEEF)),
      ],
      chat_message_id: 7,
    ),
    encode: send_chat_line.encode,
    decode: send_chat_line.decode,
  )
}

pub fn a_format_of_type_12_to_15_fails_the_read_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        12,
        "04 00 00 00 00 00 00 00 00 80 00 1e 40 60 00 80 00 00 00 00 00 00 00 00 00 80 00 00",
      ),
      #(
        13,
        "04 00 00 00 00 00 00 00 00 80 00 1e 40 68 00 80 00 00 00 00 00 00 00 00 00 80 00 00",
      ),
      #(
        14,
        "04 00 00 00 00 00 00 00 00 80 00 1e 40 70 00 80 00 00 00 00 00 00 00 00 00 80 00 00",
      ),
      #(
        15,
        "04 00 00 00 00 00 00 00 00 80 00 1e 40 78 00 80 00 00 00 00 00 00 00 00 00 80 00 00",
      ),
    ],
    fn(vector) {
      let #(tag, hex) = vector
      assert send_chat_line.decode(message_support.hex(hex))
        == Error(bit_stream.UnexpectedValue(field: "chat_format", value: tag))
        as "0x140085ca0: a type above 11 fails the client's read (cmp rax, 0xc; jnc), so the frame ends the connection"
    },
  )
}

pub fn a_text_of_more_than_127_characters_takes_the_15_bit_count_test() -> Nil {
  use <- owned_test.run(5000)
  let text = bit_stream.utf16_units(string.repeat("a", 128))
  message_support.assert_codec(
    name: "0x140336040: over 127 characters the count is a set bit and 15 bits, so 128 characters are 01 01 then the characters (vector.0x140336040.wide_text)",
    body: message_support.hex(
      "04 00 00 00 00 00 00 00 00 40 40"
      <> string.repeat(" 40 18", 128)
      <> " 00 10 00 00",
    ),
    value: SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text:,
      formats: [],
      chat_message_id: 2,
    ),
    encode: send_chat_line.encode,
    decode: send_chat_line.decode,
  )
}

pub fn a_whisper_is_a_name_a_realm_a_text_formats_a_slot_and_an_account_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1d4: 'Ab Cd', an empty realm name, 'Hi there', 0 formats, slot 3, account bit 0",
    body: message_support.hex(
      "0a 41 00 62 00 20 00 43 00 64 00 00 10 48 00 69 00 20 00 74 00 68 00 65 00 72 00 65 00 60 00 00",
    ),
    value: SendWhisper(
      target_name: bit_stream.utf16_units("Ab Cd"),
      target_realm_name: [],
      text: bit_stream.utf16_units("Hi there"),
      formats: [],
      chat_message_id: 3,
      account: 0,
    ),
    encode: send_whisper.encode,
    decode: send_whisper.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x1d4: 'Ab Cd', the realm 'Realm', an empty text, slot 0xFFFF, account bit 1",
    body: message_support.hex(
      "0a 41 00 62 00 20 00 43 00 64 00 0a 52 00 65 00 61 00 6c 00 6d 00 00 e0 ff 3f",
    ),
    value: SendWhisper(
      target_name: bit_stream.utf16_units("Ab Cd"),
      target_realm_name: bit_stream.utf16_units("Realm"),
      text: bit_stream.utf16_units(""),
      formats: [],
      chat_message_id: 0xFFFF,
      account: 1,
    ),
    encode: send_whisper.encode,
    decode: send_whisper.decode,
  )
}

pub fn the_accept_is_the_slot_the_name_the_realm_and_the_unit_with_no_item_record_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1c2: slot 5 in 16 bits, bGM 0, 0 item records in 5, 'Ab Cd', an empty realm name, unit 0x01020304 in 32, premium tier 0 in 8",
    body: message_support.hex(
      "05 00 80 42 10 80 18 00 08 c0 10 00 19 00 00 c1 80 40 00 00",
    ),
    value: ChatLineAccepted(
      chat_message_id: 5,
      gm: 0,
      name: "Ab Cd",
      realm_name: "",
      unit_id: 0x01020304,
      premium_tier: 0,
    ),
    encode: chat_line_accepted.encode,
    decode: chat_line_accepted.decode,
  )
}

pub fn a_line_to_show_is_the_channel_the_speaker_the_text_and_the_cross_faction_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1c8: type 4, id 0, bGM 0, bSelf 0, bAutoResponse 0, realm 1 in 14, character 0x0102030405060708, 'Ab Cd', an empty realm name, presence 0 in 3, 'Hello', one format of type 0 over 0 to 5 with bit 1, bCrossFaction 1, 16 bits 0, unit 0x0A0B0C0D, premium 0",
    body: message_support.hex(
      "04 00 00 00 00 00 00 00 00 00 02 00 84 03 83 02 82 01 81 00 85 20 00 31 00 10 80 21 00 32 00 00 28 20 01 94 01 b0 01 b0 01 bc 01 04 00 00 28 00 10 00 a0 81 61 41 01 00",
    ),
    value: ChatLine(
      channel_type: 4,
      channel_id: 0,
      gm: 0,
      from_self: 0,
      auto_response: 0,
      sender_realm_id: 1,
      sender_character_id: 0x0102030405060708,
      sender_name: "Ab Cd",
      sender_realm_name: "",
      presence_state: 0,
      text: bit_stream.utf16_units("Hello"),
      formats: [Kind0(ChatFormatKind0(start: 0, end: 5, field_4: 0))],
      cross_faction: 1,
      field_14: 0,
      unit_id: 0x0A0B0C0D,
      premium_tier: 0,
    ),
    encode: chat_line.encode,
    decode: chat_line.decode,
  )
}

pub fn a_result_is_the_channel_the_result_and_the_slot_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1d3: type 4, id 0, result 17 (InvalidMessageText) in 5 bits, slot 9 in 16",
    body: message_support.hex("04 00 00 00 00 00 00 00 00 40 4c 00 00"),
    value: ChatResult(
      channel_type: 4,
      channel_id: 0,
      result: chat_channel_result.InvalidMessageText,
      chat_message_id: 9,
    ),
    encode: chat_result.encode,
    decode: chat_result.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x1d3: type 9, id 0x77, result 1 (DoesntExist), slot 0xFFFF",
    body: message_support.hex("09 c0 1d 00 00 00 00 00 00 40 f8 ff 07"),
    value: ChatResult(
      channel_type: 9,
      channel_id: 0x77,
      result: chat_channel_result.DoesntExist,
      chat_message_id: 0xFFFF,
    ),
    encode: chat_result.encode,
    decode: chat_result.decode,
  )
}

pub fn a_failed_whisper_is_the_name_the_account_bit_and_the_slot_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1d9: 'Ab Cd', account bit 0, slot 5 in 16",
    body: message_support.hex("0a 41 00 62 00 20 00 43 00 64 00 0a 00 00"),
    value: WhisperFailed(
      target_name: bit_stream.utf16_units("Ab Cd"),
      account: 0,
      chat_message_id: 5,
    ),
    encode: whisper_failed.encode,
    decode: whisper_failed.decode,
  )
}

pub fn a_channel_join_is_the_type_the_id_a_name_and_three_32_bit_values_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1bc: type 9, id 0x1234, an empty name, three 32-bit values of 0",
    body: message_support.hex(
      "09 00 8d 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    ),
    value: ChatChannelJoined(
      channel_type: 9,
      channel_id: 0x1234,
      name: "",
      field_4: 0,
      field_5: 0,
      field_6: 0,
    ),
    encode: chat_channel_joined.encode,
    decode: chat_channel_joined.decode,
  )
}

pub fn the_zone_the_channels_are_named_after_is_a_15_bit_world_zone_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x1da: a WorldZone id in 15 bits, as vector.opcode.0xf2.body packs 0x1234",
    body: message_support.hex("34 12"),
    value: ChatZoneNamed(world_zone_id: 0x1234),
    encode: chat_zone_named.encode,
    decode: chat_zone_named.decode,
  )
}

pub fn a_format_of_type_8_holds_the_item_record_the_clients_reader_takes_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "0x140085ca0 and vector.0x140085510.record: type 8 in 4 bits, a range, then the record packed as ReadChatItemRecord reads it: GUID 0x1122334455667788, item id 0x2abcd, character id 0x0102030405060708, fields 4 to 10 as the vector gives them, list A 0x11111111, 0x22222222 and list B 0x33333333, 0x44444444, 0x55555555",
    body: message_support.hex(
      "04 00 00 00 00 00 00 00 00 00 41 18 80 18 40 40 00 00 01 00 c4 3b b3 2a a2 19 91 88 e6 55 11 0e 0c 0a 08 06 04 02 fe dd bb 99 77 55 33 11 f1 ac 68 24 42 86 ca 0e 53 97 db 1f e0 bd 79 35 bf 37 af 26 4a bd 81 57 44 44 44 84 88 88 88 c8 cc cc cc cc 10 11 11 11 55 55 55 55 05 00 00",
    ),
    value: SendChatLine(
      channel_type: 4,
      channel_id: 0,
      text: bit_stream.utf16_units("ab"),
      formats: [
        ItemRecord(
          ChatFormatItemRecord(
            start: 0,
            end: 2,
            item_guid: 0x1122334455667788,
            item_id: 0x2ABCD,
            character_id: 0x0102030405060708,
            field_4: 0x8899AABBCCDDEEFF,
            field_5: 0x12345678,
            field_6: 0x0FEDCBA987654321,
            field_7: 0x9ABCDEF0,
            field_8: 0x13579BDF,
            field_9: 0xA5,
            field_10: 0x3C0DE,
            list_a: [0x11111111, 0x22222222],
            list_b: [0x33333333, 0x44444444, 0x55555555],
          ),
        ),
      ],
      chat_message_id: 1,
    ),
    encode: send_chat_line.encode,
    decode: send_chat_line.decode,
  )
}
