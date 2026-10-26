//// A GUID's text and its wire bytes. The client parses each GUID from text
//// with UuidFromStringA and writes it as a 32-bit value, two 16-bit values and
//// 8 raw bytes (SendAuthLoginRequest 0x14003a620; fact file opcode.0x592 and
//// opcode.0x3db: "32, 16 and 16 bits and 8 raw bytes"), each integer
//// little-endian (WriteBits 0x140336380, bit_stream). The first three groups
//// of the text are those integers, so their bytes are reversed on the wire
//// and the last two groups keep their order.

import genesis_prime/login/guid
import gleam/string
import message_support
import owned_test
import seeded

pub fn the_text_of_a_guid_is_its_wire_bytes_with_the_first_three_groups_reversed_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(parsed) = guid.from_text("00112233-4455-6677-8899-aabbccddeeff")
    as "a GUID text parses"
  assert guid.to_wire(parsed)
    == message_support.hex("33221100 5544 7766 8899 aabbccddeeff")
    as "opcode.0x592: 32 + 16 + 16 bits little-endian then 8 raw bytes, so 00112233 is 33 22 11 00"
}

pub fn the_wire_bytes_give_the_text_back_in_lower_case_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(parsed) =
    guid.from_wire(message_support.hex("33221100 5544 7766 8899 aabbccddeeff"))
    as "sixteen bytes are a GUID"
  assert guid.to_text(parsed) == "00112233-4455-6677-8899-aabbccddeeff"
    as "the text of a GUID is its integers in hexadecimal, 8-4-4-4-12"
}

pub fn a_guid_text_in_upper_case_parses_to_the_same_bytes_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(lower) = guid.from_text("00112233-4455-6677-8899-aabbccddeeff")
    as "lower case parses"
  let assert Ok(upper) = guid.from_text("00112233-4455-6677-8899-AABBCCDDEEFF")
    as "upper case parses"
  assert lower == upper
    as "UuidFromStringA reads hexadecimal digits of either case"
}

pub fn bytes_that_are_not_sixteen_are_not_a_guid_test() -> Nil {
  use <- owned_test.run(5000)
  assert guid.from_wire(<<1, 2, 3>>) == Error(guid.NotSixteenBytes(3))
    as "opcode.0x3db: the key is 16 bytes"
  assert guid.from_wire(<<0:size(136)>>) == Error(guid.NotSixteenBytes(17))
    as "opcode.0x3db: the key is 16 bytes"
}

pub fn a_text_that_is_not_8_4_4_4_12_hexadecimal_is_not_a_guid_test() -> Nil {
  use <- owned_test.run(5000)
  let refused = [
    "",
    "00112233-4455-6677-8899-aabbccddee",
    "00112233445566778899aabbccddeeff",
    "0011223g-4455-6677-8899-aabbccddeeff",
    "00112233-4455-6677-8899-aabbccddeeff0",
  ]
  list_each(refused, fn(text) {
    assert guid.from_text(text) == Error(guid.NotGuidText(text))
      as "the text of a GUID is 8-4-4-4-12 hexadecimal, the form UuidFromStringA parses (SendAuthLoginRequest 0x14003a620); anything else is refused here"
  })
}

pub fn every_random_guid_survives_a_trip_through_its_text_test() -> Nil {
  use <- owned_test.run(10_000)
  repeat(500, 0x6A1D, fn(state) {
    let #(bytes, state) = seeded.bytes(state:, count: 16)
    let assert Ok(original) = guid.from_wire(bytes) as "16 bytes are a GUID"
    let assert Ok(again) = guid.from_text(guid.to_text(original))
      as "the text of a GUID parses"
    assert again == original as "a GUID's text names the same 16 wire bytes"
    assert string.length(guid.to_text(original)) == 36
      as "the text is 8-4-4-4-12"
    state
  })
}

fn list_each(items: List(a), body: fn(a) -> Nil) -> Nil {
  case items {
    [] -> Nil
    [first, ..rest] -> {
      body(first)
      list_each(rest, body)
    }
  }
}

fn repeat(count: Int, state: Int, body: fn(Int) -> Int) -> Nil {
  case count {
    0 -> Nil
    _ -> repeat(count - 1, body(state), body)
  }
}
