//// The bit stream primitives against the client's own bytes. The fixed values
//// are the fact file's emulator runs of the client's writers and readers:
//// `vector.0x140336380.fields` (WriteBits), `vector.0x140336040.wide_text`
//// (WriteWideText), `vector.0x1400c2f70.counted_text` (WriteCountedWideText),
//// `vector.opcode.0xf1.body` (the reader, including a body that ends inside a
//// field), and the message vectors for the GUID and the endpoint. A value too
//// wide for its field is refused when written, which the issue's test list
//// asks for; the client's own writer masks it (vector.0x140336380.fields,
//// `(0xFF, 4) -> 0f`). Every property test draws from `seeded` with a fixed
//// seed.

import genesis_prime/message/bit_stream.{Endpoint}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import message_support
import owned_test

fn written(
  values: List(#(Int, Int)),
) -> Result(BitArray, bit_stream.EncodeError) {
  list.fold(values, bit_stream.new_writer(), fn(writer, value) {
    bit_stream.write_unsigned(writer, "value", value.0, value.1)
  })
  |> bit_stream.finish
}

fn assert_written(values: List(#(Int, Int)), expected_hex: String) -> Nil {
  assert written(values) == Ok(message_support.hex(expected_hex))
    as {
      "vector.0x140336380.fields: the (value, width) calls "
      <> string.inspect(values)
      <> " leave "
      <> expected_hex
    }
  let reader =
    list.fold(
      values,
      bit_stream.new_reader(message_support.hex(expected_hex)),
      fn(reader, value) {
        let assert Ok(#(read, reader)) =
          bit_stream.read_unsigned(reader, value.1)
          as "the bytes the client's writer left hold every value"
        assert read == value.0
          as {
            "reading "
            <> int.to_string(value.1)
            <> " bits gives back the value written"
          }
        reader
      },
    )
  assert bit_stream.finish_reading(reader) == Ok(Nil)
    as "only the zero padding of the last byte is left"
}

pub fn a_one_bit_a_two_bit_a_21_bit_a_32_bit_and_a_64_bit_value_land_as_the_clients_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert_written([#(1, 1)], "01")
  assert_written([#(2, 2)], "02")
  assert_written([#(0x12345, 21)], "452301")
  assert_written([#(0xDEADBEEF, 32)], "efbeadde")
  assert_written([#(0x0123456789ABCDEF, 64)], "efcdab8967452301")
}

pub fn a_field_that_crosses_a_byte_boundary_lands_as_the_clients_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  assert_written([#(0x1F, 5), #(0x1ABCDE, 21)], "df9b5703")
  assert_written(
    [#(1, 1), #(2, 2), #(0x12345, 21), #(0xDEADBEEF, 32)],
    "2d1a09efbeadde",
  )
  assert_written([#(5, 3), #(0xFEDCBA9876543210, 64)], "8590a1b2c3d4e5f607")
  assert_written([#(0x7F, 7), #(0xABCD, 16)], "ffe655")
}

pub fn a_value_that_fits_its_width_exactly_is_written_whole_test() -> Nil {
  use <- owned_test.run(5000)
  assert_written([#(0x0F, 4)], "0f")
  assert_written([#(0xFFFFFFFFFFFFFFFF, 64)], "ffffffffffffffff")
}

pub fn a_value_wider_than_its_field_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert written([#(0xFF, 4)])
    == Error(bit_stream.ValueDoesNotFit("value", 4, 0xFF))
    as "issue test 3: a value wider than its field is refused at encode; vector.0x140336380.fields shows the client masking (0xFF, 4) to 0f"
  assert written([#(4, 2)]) == Error(bit_stream.ValueDoesNotFit("value", 2, 4))
    as "2 bits hold 0 to 3"
  assert written([#(0x1_0000_0000_0000_0000, 64)])
    == Error(bit_stream.ValueDoesNotFit("value", 64, 0x1_0000_0000_0000_0000))
    as "64 bits hold up to 0xFFFFFFFFFFFFFFFF"
  assert written([#(-1, 8)])
    == Error(bit_stream.ValueDoesNotFit("value", 8, -1))
    as "the client writes unsigned values; a negative one has no unsigned bits"
}

pub fn the_first_error_is_the_one_reported_test() -> Nil {
  use <- owned_test.run(5000)
  assert written([#(4, 2), #(8, 3), #(1, 1)])
    == Error(bit_stream.ValueDoesNotFit("value", 2, 4))
    as "a writer keeps its first error and later writes do not replace it"
}

pub fn a_wide_text_of_a_few_characters_has_a_7_bit_count_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", "Ab")
    |> bit_stream.finish
    == Ok(message_support.hex("04 41 00 62 00"))
    as "vector.0x140336040.wide_text: 'Ab' -> 04 41 00 62 00 (40 bits)"
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", "")
    |> bit_stream.finish
    == Ok(<<0>>)
    as "vector.0x140336040.wide_text: the empty text -> 00 (8 bits)"
}

pub fn a_wide_text_of_127_characters_still_has_a_7_bit_count_test() -> Nil {
  use <- owned_test.run(5000)
  let text = string.repeat("x", 127)
  let expected = <<
    0xFE,
    { string.repeat("78 00 ", 127) |> message_support.hex }:bits,
  >>
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", text)
    |> bit_stream.finish
    == Ok(expected)
    as "vector.0x140336040.wide_text: 127 'x' -> fe then 127 times 78 00 (2040 bits)"
  let reader = bit_stream.new_reader(expected)
  assert bit_stream.read_wide_text(reader) |> result_value == Ok(text)
    as "ReadWideText 0x140336a40 reads the 7-bit count and the characters"
}

pub fn a_wide_text_of_128_characters_has_a_15_bit_count_test() -> Nil {
  use <- owned_test.run(5000)
  let text = string.repeat("y", 128)
  let expected = <<
    0x01,
    0x01,
    { string.repeat("79 00 ", 128) |> message_support.hex }:bits,
  >>
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", text)
    |> bit_stream.finish
    == Ok(expected)
    as "vector.0x140336040.wide_text: 128 'y' -> 01 01 then 128 times 79 00 (2064 bits)"
  assert bit_stream.read_wide_text(bit_stream.new_reader(expected))
    |> result_value
    == Ok(text)
    as "ReadWideText 0x140336a40: a first bit of 1 means a 15-bit count"
}

pub fn a_wide_text_holds_its_characters_as_utf16_units_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", "\u{1F600}")
    |> bit_stream.finish
    == Ok(message_support.hex("04 3d d8 00 de"))
    as "WriteWideText 0x140336040 writes 16-bit units; U+1F600 is the surrogate pair D83D DE00, two units, so the count is 2 (04) and the units are little-endian"
}

pub fn a_wide_text_over_32767_units_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  let text = string.repeat("x", 32_768)
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", text)
    |> bit_stream.finish
    == Error(bit_stream.TextTooLong("text", 32_768, 32_767))
    as "WriteWideText 0x140336040 counts the units in 15 bits at most"
  let longest = string.repeat("x", 32_767)
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_text("text", longest)
    |> bit_stream.finish
    |> result.is_ok
    as "32767 units fit in 15 bits"
}

pub fn a_counted_wide_text_has_its_count_plus_one_and_a_terminating_zero_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_counted_wide_text("name", "Ab", 250)
    |> bit_stream.finish
    == Ok(message_support.hex("03 00 41 00 62 00 00 00"))
    as "vector.0x1400c2f70.counted_text: 'Ab' -> 03 00 41 00 62 00 00 00 (64 bits)"
  assert bit_stream.read_counted_wide_text(
      bit_stream.new_reader(message_support.hex("03 00 41 00 62 00 00 00")),
      250,
    )
    |> result_value
    == Ok("Ab")
    as "the same bytes read back as 'Ab'"
}

pub fn a_counted_wide_text_of_250_characters_is_written_and_251_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let longest = string.repeat("x", 250)
  let assert Ok(bytes) =
    bit_stream.new_writer()
    |> bit_stream.write_counted_wide_text("name", longest, 250)
    |> bit_stream.finish
    as "vector.0x1400c2f70.counted_text: 250 characters and a zero -> 4032 bits, result 0"
  assert bit_array.byte_size(bytes) == 504 as "4032 bits are 504 bytes"
  assert bit_stream.new_writer()
    |> bit_stream.write_counted_wide_text("name", string.repeat("x", 251), 250)
    |> bit_stream.finish
    == Error(bit_stream.TextTooLong("name", 251, 250))
    as "vector.0x1400c2f70.counted_text: 251 characters before the zero -> result 0x80070057 and nothing written"
}

pub fn a_counted_wide_text_with_a_zero_inside_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_counted_wide_text("name", "a\u{0}b", 250)
    |> bit_stream.finish
    == Error(bit_stream.TextHoldsZero("name"))
    as "WriteCountedWideText 0x1400c2f70 scans for the first zero, so a text with one inside would be cut short"
}

pub fn a_guid_is_its_sixteen_bytes_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_guid("key", message_support.session_key())
    |> bit_stream.finish
    == Ok(message_support.session_key())
    as "vector.opcode.0x58f.body: the session key 01 02 .. 10 came out as 0102030405060708090a0b0c0d0e0f10"
  assert bit_stream.read_guid(
      bit_stream.new_reader(message_support.session_key()),
    )
    |> result_value
    == Ok(message_support.session_key())
    as "ReadBytesAsBits 0x140337160: the 16 bytes of a key come back in order"
}

pub fn a_guid_that_is_not_sixteen_bytes_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_guid("key", <<1, 2, 3>>)
    |> bit_stream.finish
    == Error(bit_stream.WrongByteCount("key", 16, 3))
    as "WriteGuid 0x1400a8780 writes 32, 16 and 16 bits and 8 bytes: always 16 bytes"
}

pub fn an_endpoint_is_a_32_bit_address_then_a_16_bit_port_test() -> Nil {
  use <- owned_test.run(5000)
  let endpoint = Endpoint(address: 0x7F000001, port: 24_001)
  assert bit_stream.new_writer()
    |> bit_stream.write_endpoint("server", endpoint)
    |> bit_stream.finish
    == Ok(message_support.hex("0100007f c15d"))
    as "vector.opcode.0x7a1.body and ReadIpv4Endpoint 0x1400a8980: 127.0.0.1 port 24001 is 0100007f c15d"
  assert bit_stream.read_endpoint(
      bit_stream.new_reader(message_support.hex("0100007f c15d")),
    )
    |> result_value
    == Ok(endpoint)
    as "vector.opcode.0x7a1.body: the endpoint reads back as 0x7f000001 and 24001"
}

pub fn a_float32_is_kept_as_its_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_float32_bits("value", 0xC0200000)
    |> bit_stream.finish
    == Ok(message_support.hex("00 00 20 c0"))
    as "ReadFloat 0x14006c1c0 keeps the 32 bits as they are; -2.5 is 0xC0200000, and vector.opcode.0xad.body holds it"
  assert bit_stream.read_float32_bits(
      bit_stream.new_reader(message_support.hex("00 00 20 c0")),
    )
    |> result_value
    == Ok(0xC0200000)
    as "the bits come back as the same number, with no conversion"
  assert bit_stream.new_writer()
    |> bit_stream.write_float32_bits("value", 0x1_0000_0000)
    |> bit_stream.finish
    == Error(bit_stream.ValueDoesNotFit("value", 32, 0x1_0000_0000))
    as "a float's bits are 32"
}

pub fn an_empty_array_is_only_its_count_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_texts("texts", [], 32)
    |> bit_stream.finish
    == Ok(<<0, 0, 0, 0>>)
    as "vector.opcode.0x761.body: with no realms and no groups, each 32-bit count is 00000000"
  assert bit_stream.read_wide_texts(bit_stream.new_reader(<<0, 0, 0, 0>>), 32)
    |> result_value
    == Ok([])
    as "a count of zero is an empty list"
  assert bit_stream.new_writer()
    |> bit_stream.write_array("items", [], 32, fn(writer, _item: Int) { writer })
    |> bit_stream.finish
    == Ok(<<0, 0, 0, 0>>)
    as "an empty array of any item is only its count"
}

pub fn an_array_is_its_count_then_each_item_test() -> Nil {
  use <- owned_test.run(5000)
  let texts = ["d", "bc"]
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_texts("texts", texts, 8)
    |> bit_stream.finish
    == Ok(message_support.hex("02 02 6400 04 6200 6300"))
    as "vector.opcode.0x761.body: a text group holds an 8-bit count of 2, then 'd' and 'bc' as wide texts"
  assert bit_stream.read_wide_texts(
      bit_stream.new_reader(message_support.hex("02 02 6400 04 6200 6300")),
      8,
    )
    |> result_value
    == Ok(texts)
    as "ReadRealmListTextGroup 0x1400ac590 reads them back"
}

pub fn an_array_longer_than_its_count_can_hold_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  let texts = list.repeat("a", 256)
  assert bit_stream.new_writer()
    |> bit_stream.write_wide_texts("texts", texts, 8)
    |> bit_stream.finish
    == Error(bit_stream.ValueDoesNotFit("texts", 8, 256))
    as "ReadRealmListTextGroup 0x1400ac590: the count is 8 bits, so 255 texts at most"
}

pub fn a_whole_frame_is_written_from_the_next_whole_byte_test() -> Nil {
  use <- owned_test.run(5000)
  let frame = <<6, 0, 0, 0, 0xE0, 0x07>>
  assert bit_stream.new_writer()
    |> bit_stream.write_unsigned("value", 3, 5)
    |> bit_stream.write_whole_frame("frame", frame)
    |> bit_stream.finish
    == Ok(<<3, 6, 0, 0, 0, 0xE0, 0x07>>)
    as "opcode.0x38c and WriteMessage038CBody 0x14007e1c0: a 5-bit value, then the inner frame from the next whole byte"
  let reader = bit_stream.new_reader(<<3, 6, 0, 0, 0, 0xE0, 0x07>>)
  let assert Ok(#(value, reader)) = bit_stream.read_unsigned(reader, 5)
    as "the 5-bit value reads"
  assert value == 3
  assert bit_stream.read_whole_frame(reader) |> result_value == Ok(frame)
    as "ReadWholeFrameBody 0x140079f70 takes the inner frame's length bytes"
}

pub fn a_whole_frame_whose_length_is_not_its_size_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_whole_frame("frame", <<9, 0, 0, 0, 1, 2>>)
    |> bit_stream.finish
    == Error(bit_stream.InnerFrameDisagrees("frame"))
    as "WriteWholeFrameBody 0x140079f30 copies from the frame to the end its first dword gives"
}

pub fn a_whole_frame_that_claims_more_bytes_than_there_are_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.read_whole_frame(
      bit_stream.new_reader(<<9, 0, 0, 0, 1, 2>>),
    )
    |> result_value
    == Error(bit_stream.EndOfData)
    as "ReadWholeFrameBody 0x140079f70 copies the length the first dword gives; the bytes end first"
  assert bit_stream.read_whole_frame(bit_stream.new_reader(<<3, 0, 0, 0>>))
    |> result_value
    == Error(bit_stream.InnerFrameTooShort(3))
    as "a frame's length counts its own 4 bytes"
}

pub fn bytes_ending_inside_a_field_are_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  let body = message_support.hex("e359d148acd207000000")
  assert reads_message_f1_fields(body) == Ok(#(3, 0x12345678, 0xAB, 500))
    as "vector.opcode.0xf1.body: 3 (2 bits), 0x12345678 (32 bits), 0xAB (8 bits) and 500 (32 bits) read back"
  let assert Ok(first_nine) = bit_array.slice(body, 0, 9)
    as "the first nine bytes exist"
  assert reads_message_f1_fields(first_nine) == Error(bit_stream.EndOfData)
    as "vector.opcode.0xf1.body: the first 9 bytes alone fail with 0x80070026 after 72 bits"
  assert bit_stream.read_unsigned(bit_stream.new_reader(<<>>), 1)
    == Error(bit_stream.EndOfData)
    as "no bits at all hold not even one"
  assert bit_stream.read_unsigned(bit_stream.new_reader(<<0xFF>>), 9)
    == Error(bit_stream.EndOfData)
    as "ReadBitsSlow 0x140336d60 returns 0x80070026 when the received data ends first"
}

pub fn a_wide_text_whose_count_runs_past_the_bytes_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.read_wide_text(
      bit_stream.new_reader(message_support.hex("0a 4e00 6500")),
    )
    |> result_value
    == Error(bit_stream.EndOfData)
    as "ReadWideText 0x140336a40 reads count characters; 5 were counted and 2 are there"
}

pub fn a_wide_text_with_a_lone_surrogate_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.read_wide_text(
      bit_stream.new_reader(message_support.hex("02 3dd8")),
    )
    |> result_value
    == Error(bit_stream.InvalidText)
    as "a UTF-16 unit D83D with no low surrogate after it is not a character a Gleam string can hold"
  assert bit_stream.read_wide_text(
      bit_stream.new_reader(message_support.hex("02 00de")),
    )
    |> result_value
    == Error(bit_stream.InvalidText)
    as "a low surrogate DE00 with no high one before it is not a character either"
}

pub fn a_counted_wide_text_that_does_not_end_in_its_zero_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.read_counted_wide_text(
      bit_stream.new_reader(message_support.hex("03 00 41 00 62 00 63 00")),
      250,
    )
    |> result_value
    == Error(bit_stream.InvalidCountedText)
    as "WriteCountedWideText 0x1400c2f70 writes count plus one units, the last of them zero"
  assert bit_stream.read_counted_wide_text(
      bit_stream.new_reader(message_support.hex("03 00 41 00 00 00 00 00")),
      250,
    )
    |> result_value
    == Error(bit_stream.InvalidCountedText)
    as "a zero before the last unit means the text the client wrote was cut short there"
  assert bit_stream.read_counted_wide_text(
      bit_stream.new_reader(message_support.hex("00 00")),
      250,
    )
    |> result_value
    == Error(bit_stream.InvalidCountedText)
    as "the count is the characters plus one, so it is never zero"
  let long = <<
    252:size(16)-little,
    { string.repeat("78 00 ", 252) |> message_support.hex }:bits,
  >>
  assert bit_stream.read_counted_wide_text(bit_stream.new_reader(long), 250)
    |> result_value
    == Error(bit_stream.InvalidCountedText)
    as "a count over the maximum plus one is not a text the client could have written"
}

pub fn whole_bytes_left_after_the_last_field_are_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(#(_, reader)) =
    bit_stream.read_unsigned(bit_stream.new_reader(<<0xAB, 0xCD>>), 3)
    as "three bits read"
  assert bit_stream.finish_reading(reader) == Error(bit_stream.TrailingBytes(1))
    as "a body ends on the byte after its last field; the second byte is left over"
  let assert Ok(#(_, reader)) =
    bit_stream.read_unsigned(bit_stream.new_reader(<<0xAB>>), 3)
    as "three bits read"
  assert bit_stream.finish_reading(reader) == Ok(Nil)
    as "the rest of the last byte is padding (WriteMessageFrame 0x1403355e0)"
}

pub fn random_runs_of_fields_read_back_as_written_test() -> Nil {
  use <- owned_test.run(60_000)
  let checked =
    int.range(from: 0, to: 1000, with: #(20_261_027, 0), run: fn(state, _case) {
      let #(random, checked) = state
      let #(count, random) = message_support.up_to(state: random, most: 12)
      let #(fields, random) =
        message_support.draw_list(state: random, count:, draw: draw_field)
      let written =
        list.fold(fields, bit_stream.new_writer(), write_field)
        |> bit_stream.finish
      let assert Ok(bytes) = written
        as "every field is within its width, so the run is written"
      let reader =
        list.fold(fields, bit_stream.new_reader(bytes), assert_field_reads_back)
      assert bit_stream.finish_reading(reader) == Ok(Nil)
        as "the last field ends within the last byte, so nothing whole is left"
      #(random, checked + 1)
    })
  assert checked.1 == 1000 as "every generated run was checked"
}

/// A field of a random run: what kind and what value, so fields of every width
/// start at every bit offset.
type Field {
  UnsignedField(bits: Int, value: Int)
  TextField(String)
  RawField(BitArray)
  GuidField(BitArray)
  EndpointField(bit_stream.Endpoint)
}

fn draw_field(state: Int) -> #(Field, Int) {
  let #(kind, state) = message_support.up_to(state:, most: 4)
  case kind {
    0 | 1 -> {
      let #(bits, state) = message_support.up_to(state:, most: 63)
      let #(value, state) = message_support.unsigned(state:, bits: bits + 1)
      #(UnsignedField(bits + 1, value), state)
    }
    2 -> {
      let #(text, state) = message_support.field_text(state:)
      #(TextField(text), state)
    }
    3 -> {
      let #(count, state) = message_support.up_to(state:, most: 20)
      let #(bytes, state) = message_support.bytes(state:, count:)
      #(RawField(bytes), state)
    }
    _ -> {
      let #(guid, state) = message_support.guid(state:)
      let #(endpoint, state) = message_support.endpoint(state:)
      case state % 2 {
        0 -> #(GuidField(guid), state)
        _ -> #(EndpointField(endpoint), state)
      }
    }
  }
}

fn write_field(writer: bit_stream.Writer, field: Field) -> bit_stream.Writer {
  case field {
    UnsignedField(bits:, value:) ->
      bit_stream.write_unsigned(writer, "value", value, bits)
    TextField(text) -> bit_stream.write_wide_text(writer, "text", text)
    RawField(bytes) ->
      bit_stream.write_raw_bytes(
        writer,
        "bytes",
        bytes,
        bit_array.byte_size(bytes),
      )
    GuidField(guid) -> bit_stream.write_guid(writer, "guid", guid)
    EndpointField(endpoint) ->
      bit_stream.write_endpoint(writer, "endpoint", endpoint)
  }
}

fn assert_field_reads_back(
  reader: bit_stream.Reader,
  field: Field,
) -> bit_stream.Reader {
  case field {
    UnsignedField(bits:, value:) -> {
      let assert Ok(#(read, reader)) = bit_stream.read_unsigned(reader, bits)
        as "the written bits are there"
      assert read == value as "an unsigned value reads back as written"
      reader
    }
    TextField(text) -> {
      let assert Ok(#(read, reader)) = bit_stream.read_wide_text(reader)
        as "the written text is there"
      assert read == text as "a wide text reads back as written"
      reader
    }
    RawField(bytes) -> {
      let assert Ok(#(read, reader)) =
        bit_stream.read_raw_bytes(reader, bit_array.byte_size(bytes))
        as "the written bytes are there"
      assert read == bytes as "raw bytes read back in order at any bit offset"
      reader
    }
    GuidField(guid) -> {
      let assert Ok(#(read, reader)) = bit_stream.read_guid(reader)
        as "the written key is there"
      assert read == guid as "a GUID reads back as written"
      reader
    }
    EndpointField(endpoint) -> {
      let assert Ok(#(read, reader)) = bit_stream.read_endpoint(reader)
        as "the written endpoint is there"
      assert read == endpoint as "an endpoint reads back as written"
      reader
    }
  }
}

/// The four fields of message 0xF1 read from a body, as `ReadMessage00F1Body`
/// 0x1400a37d0 does: 2, 32, 8 and 32 bits.
fn reads_message_f1_fields(
  body: BitArray,
) -> Result(#(Int, Int, Int, Int), bit_stream.DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(first, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(second, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(third, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(fourth, _reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(first, second, third, fourth))
}

fn result_value(result: Result(#(a, bit_stream.Reader), e)) -> Result(a, e) {
  case result {
    Ok(#(value, _reader)) -> Ok(value)
    Error(error) -> Error(error)
  }
}
