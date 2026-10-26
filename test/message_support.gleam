//// Shared by the message tests: hexadecimal vectors and a seeded source of
//// values of every field kind, each within the field's width.

import connection_vectors
import genesis_prime/message/bit_stream.{type Endpoint, Endpoint}
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
