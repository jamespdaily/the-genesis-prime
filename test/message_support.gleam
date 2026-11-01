//// Shared by the message tests: hexadecimal vectors, checked against the fact
//// file's records that state them.

import connection_vectors
import fact_file
import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/bit_array
import gleam/int
import gleam/string

/// The bytes of a vector written as hexadecimal groups, spaces ignored, as the
/// fact file's `vector.*` records write them.
pub fn hex(text: String) -> BitArray {
  connection_vectors.hex(string.replace(text, " ", ""))
}

/// The bytes 01 02 .. 10, the session key of the fact file's vectors.
pub fn session_key() -> BitArray {
  <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
}

/// Checks a message against a body vector of the fact file. `name` is the key
/// of the record that gives the bytes, which must state them (`fact_file`): a
/// record that is missing, or whose statement gives other bytes, fails the
/// test. Then `assert_codec` checks the message against the bytes.
pub fn assert_vector(
  name name: String,
  body body: BitArray,
  value value: a,
  encode encode: fn(a) -> Result(BitArray, EncodeError),
  decode decode: fn(BitArray) -> Result(a, DecodeError),
) -> Nil {
  assert fact_file.gives(record: name, bytes: body) == Ok(Nil)
    as {
      name
      <> ": the fact file has this record, and its statement gives these bytes: "
      <> bit_array.base16_encode(body)
    }
  assert_codec(name:, body:, value:, encode:, decode:)
}

/// Checks a message against the bytes of its body: the bytes decode to the
/// values, the values encode back to the same bytes, and every shorter run of
/// the bytes, one that ends inside a field, is a decode error, as the client's
/// reader fails with 0x80070026 (ReadBitsSlow 0x140336D60). `name` says what
/// gives the bytes.
pub fn assert_codec(
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

/// The bytes with `width` bits from the bit `at` (counted from the first bit of
/// the first byte, least significant bit first, as the client's bit stream
/// does) set to `value`.
pub fn set_bits(
  body body: BitArray,
  at at: Int,
  width width: Int,
  to value: Int,
) -> BitArray {
  let size = bit_array.byte_size(body) * 8
  let assert <<number:size(size)-little>> = body
    as "a whole number of bytes is a number"
  let mask = int.bitwise_shift_left(int.bitwise_shift_left(1, width) - 1, at)
  let cleared = int.bitwise_and(number, int.bitwise_not(mask))
  let changed = int.bitwise_or(cleared, int.bitwise_shift_left(value, at))
  <<changed:size(size)-little>>
}
