//// Shared by the message tests: hexadecimal vectors and a seeded source of
//// values of every field kind, each within the field's width.

import connection_vectors
import genesis_prime/message/bit_stream.{
  type DecodeError, type EncodeError, type Endpoint, Endpoint,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import seeded

/// The bytes of a vector written as hexadecimal groups, spaces ignored, as the
/// fact file's `vector.*` records write them.
pub fn hex(text: String) -> BitArray {
  connection_vectors.hex(string.replace(text, " ", ""))
}

/// The bytes 01 02 .. 10, the session key of the fact file's vectors.
pub fn session_key() -> BitArray {
  <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>
}

/// An unsigned value of `bits` bits and the advanced state.
pub fn unsigned(state state: Int, bits bits: Int) -> #(Int, Int) {
  let #(value, state) = seeded.next(state)
  #(int.bitwise_and(value, int.bitwise_shift_left(1, bits) - 1), state)
}

/// A value from 0 up to and including `most`, and the advanced state.
pub fn up_to(state state: Int, most most: Int) -> #(Int, Int) {
  seeded.up_to(state:, most:)
}

/// A text of up to `longest` characters that holds none of U+0000 and no
/// surrogate: mostly ASCII, some of the basic plane, some above it, so UTF-16
/// units and characters differ.
pub fn text(state state: Int, longest longest: Int) -> #(String, Int) {
  let #(length, state) = seeded.up_to(state:, most: longest)
  characters(state:, remaining: length, built: [])
}

fn characters(
  state state: Int,
  remaining remaining: Int,
  built built: List(UtfCodepoint),
) -> #(String, Int) {
  case remaining {
    0 -> #(string.from_utf_codepoints(built), state)
    _ -> {
      let #(kind, state) = seeded.up_to(state:, most: 9)
      let #(number, state) = case kind {
        0 -> {
          let #(value, state) = seeded.up_to(state:, most: 0x10FFFF - 0x10000)
          #(value + 0x10000, state)
        }
        1 | 2 -> {
          let #(value, state) = seeded.up_to(state:, most: 0xD7FF - 0x80)
          #(value + 0x80, state)
        }
        _ -> {
          let #(value, state) = seeded.up_to(state:, most: 126)
          #(value + 1, state)
        }
      }
      let assert Ok(codepoint) = string.utf_codepoint(number)
        as "the drawn number is a character"
      characters(state:, remaining: remaining - 1, built: [codepoint, ..built])
    }
  }
}

/// A text for a field: usually short, sometimes over 127 UTF-16 units so the
/// 15-bit count is used.
pub fn field_text(state state: Int) -> #(String, Int) {
  let #(kind, state) = seeded.up_to(state:, most: 7)
  case kind {
    0 -> {
      let #(short, state) = text(state:, longest: 300)
      let #(long, state) = text(state:, longest: 40)
      #(short <> long, state)
    }
    _ -> text(state:, longest: 40)
  }
}

/// `count` random bytes and the advanced state.
pub fn bytes(state state: Int, count count: Int) -> #(BitArray, Int) {
  seeded.bytes(state:, count:)
}

/// A 16-byte GUID.
pub fn guid(state state: Int) -> #(BitArray, Int) {
  seeded.bytes(state:, count: 16)
}

/// An address of 32 bits and a port of 16 bits.
pub fn endpoint(state state: Int) -> #(Endpoint, Int) {
  let #(address, state) = unsigned(state:, bits: 32)
  let #(port, state) = unsigned(state:, bits: 16)
  #(Endpoint(address:, port:), state)
}

/// A whole inner frame: its length in 4 little-endian bytes, counting
/// themselves, then bytes up to 300 long.
pub fn frame(state state: Int) -> #(BitArray, Int) {
  let #(extra, state) = seeded.up_to(state:, most: 300)
  let #(body, state) = seeded.bytes(state:, count: extra)
  let length = 4 + extra
  #(<<length:size(32)-little, body:bits>>, state)
}

/// Draws `count` values with one generator and keeps them in order.
pub fn draw_list(
  state state: Int,
  count count: Int,
  draw draw: fn(Int) -> #(a, Int),
) -> #(List(a), Int) {
  let #(items, state) =
    int.range(from: 0, to: count, with: #([], state), run: fn(acc, _) {
      let #(items, state) = acc
      let #(item, state) = draw(state)
      #([item, ..items], state)
    })
  #(list.reverse(items), state)
}

/// Checks a message against a body vector of the fact file: the bytes decode to
/// the values the record gives, the values encode back to the same bytes, and
/// every shorter run of the bytes, one that ends inside a field, is a decode
/// error, as the client's reader fails with 0x80070026 (ReadBitsSlow
/// 0x140336D60).
pub fn assert_vector(
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

/// How many seeded messages each round-trip test draws.
const round_trip_cases = 1000

/// Checks a message kind over `round_trip_cases` seeded draws: each message
/// encodes, the bytes decode to the message, and encoding it again gives the
/// same bytes.
pub fn round_trips(
  name name: String,
  seed seed: Int,
  draw draw: fn(Int) -> #(a, Int),
  encode encode: fn(a) -> Result(BitArray, EncodeError),
  decode decode: fn(BitArray) -> Result(a, DecodeError),
) -> Nil {
  let checked =
    int.range(
      from: 0,
      to: round_trip_cases,
      with: #(seed, 0),
      run: fn(state, number) {
        let #(random, checked) = state
        let #(message, random) = draw(random)
        let assert Ok(bytes) = encode(message)
          as {
            name
            <> " case "
            <> int.to_string(number)
            <> ": every field is within its width, so the message encodes"
          }
        assert decode(bytes) == Ok(message)
          as {
            name
            <> " case "
            <> int.to_string(number)
            <> ": the bytes decode to the message encoded"
          }
        assert encode(message) == Ok(bytes)
          as {
            name
            <> " case "
            <> int.to_string(number)
            <> ": encoding is repeatable"
          }
        #(random, checked + 1)
      },
    )
  assert checked.1 == round_trip_cases as "every generated case was checked"
}
