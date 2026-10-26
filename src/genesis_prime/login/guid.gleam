//// A GUID as the client sends it and the server keeps it. The client parses
//// each GUID from its text with UuidFromStringA and writes it as a 32-bit,
//// two 16-bit and 8 raw bytes, each integer little-endian, so the 16 bytes on
//// the wire are the Windows GUID structure's bytes (opcode.0x592 and
//// opcode.0x3db: "32, 16 and 16 bits and 8 raw bytes"; SendAuthLoginRequest
//// 0x14003a620). The text is the usual 8-4-4-4-12 hexadecimal: its first group
//// is the structure's 32-bit integer, so it is the first four bytes reversed.

import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// A GUID in the order of its wire bytes.
pub opaque type Guid {
  Guid(wire: BitArray)
}

/// Why bytes or a text are not a GUID.
pub type GuidError {
  /// A GUID is 16 bytes on the wire.
  NotSixteenBytes(bytes: Int)
  /// The text is not 8-4-4-4-12 hexadecimal.
  NotGuidText(text: String)
}

/// The GUID whose wire bytes these are.
pub fn from_wire(bytes bytes: BitArray) -> Result(Guid, GuidError) {
  case bit_array.byte_size(bytes) {
    16 -> Ok(Guid(wire: bytes))
    size -> Error(NotSixteenBytes(size))
  }
}

/// The 16 wire bytes of a GUID.
pub fn to_wire(guid guid: Guid) -> BitArray {
  guid.wire
}

/// The GUID a text names, as UuidFromStringA reads it.
pub fn from_text(text text: String) -> Result(Guid, GuidError) {
  let refused = NotGuidText(text:)
  case string.split(text, "-") {
    [first, second, third, fourth, fifth] ->
      case
        string.length(first) == 8
        && string.length(second) == 4
        && string.length(third) == 4
        && string.length(fourth) == 4
        && string.length(fifth) == 12
        && list.all(string.to_graphemes(text), is_digit_or_dash)
      {
        True -> {
          use first <- result.try(hexadecimal(first, refused))
          use second <- result.try(hexadecimal(second, refused))
          use third <- result.try(hexadecimal(third, refused))
          use fourth <- result.try(hexadecimal(fourth, refused))
          use fifth <- result.map(hexadecimal(fifth, refused))
          Guid(wire: <<
            first:size(32)-little,
            second:size(16)-little,
            third:size(16)-little,
            fourth:size(16)-big,
            fifth:size(48)-big,
          >>)
        }
        False -> Error(refused)
      }
    _ -> Error(refused)
  }
}

fn hexadecimal(digits: String, refused: GuidError) -> Result(Int, GuidError) {
  int.base_parse(digits, 16) |> result.replace_error(refused)
}

fn is_digit_or_dash(grapheme: String) -> Bool {
  string.contains("0123456789abcdefABCDEF-", grapheme)
}

/// The text of a GUID in lower-case hexadecimal, 8-4-4-4-12.
pub fn to_text(guid guid: Guid) -> String {
  let assert <<
    first:size(32)-little,
    second:size(16)-little,
    third:size(16)-little,
    fourth:size(16)-big,
    fifth:size(48)-big,
  >> = guid.wire
    as "a GUID holds 16 bytes"
  string.join(
    [
      digits(first, 8),
      digits(second, 4),
      digits(third, 4),
      digits(fourth, 4),
      digits(fifth, 12),
    ],
    "-",
  )
}

fn digits(value: Int, width: Int) -> String {
  int.to_base16(value) |> string.lowercase |> string.pad_start(width, "0")
}
