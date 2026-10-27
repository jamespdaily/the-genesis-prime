//// How a message body is written and read: a stream of bits, each value in the
//// least significant bit first, so a value that starts on a byte boundary and
//// is 16, 32 or 64 bits wide lands as little-endian bytes, and a field may
//// start and end anywhere in a byte (WriteBits 0x140336380, ReadBits32
//// 0x14006c090). A body ends on a byte boundary, the last byte padded with
//// zero bits (WriteMessageFrame 0x1403355e0).
////
//// The generated message modules call these functions in the order of their
//// fields. A writer keeps the first error, and every later write leaves it
//// alone, so a generated encoder is one pipeline and `finish` gives the bytes
//// or that error. A reader returns each value with the reader after it, so a
//// generated decoder stops at the first field the bytes cannot hold.

import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A server's address and port as the client reads them (ReadIpv4Endpoint
/// 0x1400a8980): the address as a number, so 127.0.0.1 is 0x7F000001, and the
/// port.
pub type Endpoint {
  Endpoint(address: Int, port: Int)
}

/// Why a value could not be written. Each is the caller's value being wrong,
/// not the bytes, so nothing is sent.
pub type EncodeError {
  /// A value is negative or needs more than the field's bits.
  ValueDoesNotFit(field: String, bits: Int, value: Int)
  /// Raw bytes or a GUID are not the field's fixed number of bytes.
  WrongByteCount(field: String, expected: Int, actual: Int)
  /// A text has more UTF-16 units than its form can count (WriteWideText
  /// 0x140336040 counts them in 15 bits, WriteCountedWideText 0x1400c2f70 in a
  /// given maximum).
  TextTooLong(field: String, units: Int, limit: Int)
  /// A counted text holds a zero, where the client's writer would stop.
  TextHoldsZero(field: String)
  /// A whole frame's first 32 bits are not its length in bytes, or it is not
  /// whole bytes (WriteWholeFrameBody 0x140079f30).
  InnerFrameDisagrees(field: String)
  /// A list that has no count of its own is not as long as the list that
  /// counts it (the customisation values and labels of a character).
  ItemCountDisagrees(field: String, expected: Int, actual: Int)
  /// A value is at or above the limit the schema sets below the field's width,
  /// such as a sequence number that counts to 19.
  ValueAtOrAboveLimit(field: String, limit: Int, value: Int)
}

/// Why bytes are not a body. A decode error ends the connection.
pub type DecodeError {
  /// The bytes end inside a field; the client's reader fails the same way with
  /// 0x80070026 (ReadBitsSlow 0x140336d60).
  EndOfData
  /// Whole bytes are left after the last field.
  TrailingBytes(count: Int)
  /// A text is not valid UTF-16: a surrogate without its pair.
  InvalidText
  /// A counted text does not end in its zero, holds a zero before it, or is
  /// longer than its maximum.
  InvalidCountedText
  /// A whole frame's length is below the 4 bytes of the length itself.
  InnerFrameTooShort(length: Int)
  /// A field the schema fixes to one value holds another, or holds a value at
  /// or above the limit the schema sets.
  UnexpectedValue(field: String, value: Int)
}

/// A sentence that says why a value could not be written, for the log.
pub fn describe_encode(error error: EncodeError) -> String {
  case error {
    ValueDoesNotFit(field:, bits:, value:) ->
      "the value "
      <> int.to_string(value)
      <> " of "
      <> field
      <> " does not fit in "
      <> int.to_string(bits)
      <> " bits"
    WrongByteCount(field:, expected:, actual:) ->
      field
      <> " has "
      <> int.to_string(actual)
      <> " bytes, not "
      <> int.to_string(expected)
    TextTooLong(field:, units:, limit:) ->
      "the text "
      <> field
      <> " has "
      <> int.to_string(units)
      <> " units, over the limit of "
      <> int.to_string(limit)
    TextHoldsZero(field:) -> "the counted text " <> field <> " holds a zero"
    InnerFrameDisagrees(field:) ->
      "the whole frame " <> field <> " disagrees with its length"
    ItemCountDisagrees(field:, expected:, actual:) ->
      field
      <> " has "
      <> int.to_string(actual)
      <> " items, not "
      <> int.to_string(expected)
    ValueAtOrAboveLimit(field:, limit:, value:) ->
      "the value "
      <> int.to_string(value)
      <> " of "
      <> field
      <> " is at or above its limit of "
      <> int.to_string(limit)
  }
}

/// A sentence that says why bytes are not a body, for the log.
pub fn describe_decode(error error: DecodeError) -> String {
  case error {
    EndOfData -> "the bytes end inside a field"
    TrailingBytes(count:) ->
      int.to_string(count) <> " bytes are left after the last field"
    InvalidText -> "a text is not valid UTF-16"
    InvalidCountedText -> "a counted text is not well formed"
    InnerFrameTooShort(length:) ->
      "a whole frame's length of "
      <> int.to_string(length)
      <> " is below its own 4 bytes"
    UnexpectedValue(field:, value:) ->
      "the field "
      <> field
      <> " holds the unexpected value "
      <> int.to_string(value)
  }
}

/// A body being written: the whole bytes written, the bits that do not fill
/// a byte, and the first error.
pub opaque type Writer {
  Writer(
    whole_bytes: BitArray,
    pending: Int,
    pending_bits: Int,
    failure: Option(EncodeError),
  )
}

/// A body being read: the bytes and the bit position of the next value.
pub opaque type Reader {
  Reader(bytes: BitArray, position: Int)
}

/// The most UTF-16 units a wide text can count: the count is 7 or 15 bits.
const max_wide_text_units = 32_767

/// A writer with nothing written.
pub fn new_writer() -> Writer {
  Writer(whole_bytes: <<>>, pending: 0, pending_bits: 0, failure: None)
}

/// The bytes written, the last one padded with zero bits, or the first error.
pub fn finish(writer: Writer) -> Result(BitArray, EncodeError) {
  case writer.failure, writer.pending_bits {
    Some(error), _ -> Error(error)
    None, 0 -> Ok(writer.whole_bytes)
    None, _ -> Ok(<<writer.whole_bytes:bits, writer.pending:size(8)>>)
  }
}

/// Writes an unsigned value in `bits` bits, 1 to 64; a value that is negative
/// or does not fit is an error.
pub fn write_unsigned(
  writer writer: Writer,
  field field: String,
  value value: Int,
  bits bits: Int,
) -> Writer {
  assert bits >= 1 && bits <= 64
    as "a field's width is 1 to 64 bits, and the schema says which"
  use <- bool.guard(
    when: value < 0 || value >= int.bitwise_shift_left(1, bits),
    return: fail(writer:, error: ValueDoesNotFit(field:, bits:, value:)),
  )
  put(writer:, value:, bits:)
}

/// Writes the bits of a 32-bit float, kept as the number they are (ReadFloat
/// 0x14006c1c0): no conversion, so every bit pattern round-trips.
pub fn write_float32_bits(
  writer writer: Writer,
  field field: String,
  bits bits: Int,
) -> Writer {
  write_unsigned(writer:, field:, value: bits, bits: 32)
}

/// Writes a wide text: one bit that is set when it has more than 127 UTF-16
/// units, their count in 7 bits or 15 bits, then each unit in 16 bits
/// (WriteWideText 0x140336040).
pub fn write_wide_text(
  writer writer: Writer,
  field field: String,
  text text: String,
) -> Writer {
  let units = utf16_units(text)
  let count = list.length(units)
  use <- bool.guard(
    when: count > max_wide_text_units,
    return: fail(
      writer:,
      error: TextTooLong(field:, units: count, limit: max_wide_text_units),
    ),
  )
  let counted = case count > 127 {
    True -> writer |> put(value: 1, bits: 1) |> put(value: count, bits: 15)
    False -> writer |> put(value: 0, bits: 1) |> put(value: count, bits: 7)
  }
  put_units(writer: counted, units:)
}

/// Writes a counted wide text: the count of units plus one in 16 bits, then the
/// units and a terminating zero in 16 bits each (WriteCountedWideText
/// 0x1400c2f70). `max_units` is the most units the message allows.
pub fn write_counted_wide_text(
  writer writer: Writer,
  field field: String,
  text text: String,
  max_units max_units: Int,
) -> Writer {
  let units = utf16_units(text)
  let count = list.length(units)
  use <- bool.guard(
    when: list.contains(units, 0),
    return: fail(writer:, error: TextHoldsZero(field:)),
  )
  use <- bool.guard(
    when: count > max_units,
    return: fail(
      writer:,
      error: TextTooLong(field:, units: count, limit: max_units),
    ),
  )
  writer
  |> put(value: count + 1, bits: 16)
  |> put_units(units:)
  |> put(value: 0, bits: 16)
}

/// Writes a GUID: 16 bytes in their order (WriteGuid 0x1400a8780).
pub fn write_guid(
  writer writer: Writer,
  field field: String,
  guid guid: BitArray,
) -> Writer {
  write_raw_bytes(writer:, field:, bytes: guid, count: 16)
}

/// Writes raw bytes at the bit position, with no move to a byte boundary, in
/// order (WriteBytesAsBits 0x1403360d0); there must be exactly `count`.
pub fn write_raw_bytes(
  writer writer: Writer,
  field field: String,
  bytes bytes: BitArray,
  count count: Int,
) -> Writer {
  let actual = bit_array.bit_size(bytes)
  use <- bool.guard(
    when: actual != count * 8,
    return: fail(
      writer:,
      error: WrongByteCount(field:, expected: count, actual: actual / 8),
    ),
  )
  put_bytes(writer:, bytes:)
}

/// Writes a server's address in 32 bits and its port in 16.
pub fn write_endpoint(
  writer writer: Writer,
  field field: String,
  endpoint endpoint: Endpoint,
) -> Writer {
  writer
  |> write_unsigned(field:, value: endpoint.address, bits: 32)
  |> write_unsigned(field:, value: endpoint.port, bits: 16)
}

/// Writes a whole inner frame, its 32-bit length counting its own 4 bytes
/// included, after moving to the next whole byte (WriteRawBytes 0x1403365e0).
pub fn write_whole_frame(
  writer writer: Writer,
  field field: String,
  frame frame: BitArray,
) -> Writer {
  let size = bit_array.byte_size(frame)
  case bit_array.bit_size(frame) == size * 8, frame {
    True, <<length:size(32)-little, _:bytes>> if length == size ->
      writer |> align |> put_bytes(bytes: frame)
    _, _ -> fail(writer:, error: InnerFrameDisagrees(field:))
  }
}

/// Writes the items' count in `count_bits` bits, then each item through
/// `write_item`.
pub fn write_array(
  writer writer: Writer,
  field field: String,
  items items: List(a),
  count_bits count_bits: Int,
  write_item write_item: fn(Writer, a) -> Writer,
) -> Writer {
  let counted =
    write_unsigned(writer:, field:, value: list.length(items), bits: count_bits)
  list.fold(items, counted, write_item)
}

/// Writes an unsigned value in `bits` bits that the schema limits to below
/// `limit`; a value at or above the limit is an error.
pub fn write_unsigned_below(
  writer writer: Writer,
  field field: String,
  value value: Int,
  bits bits: Int,
  limit limit: Int,
) -> Writer {
  use <- bool.guard(
    when: value >= limit,
    return: fail(writer:, error: ValueAtOrAboveLimit(field:, limit:, value:)),
  )
  write_unsigned(writer:, field:, value:, bits:)
}

/// Writes a value the schema fixes, in `bits` bits.
pub fn write_constant(
  writer writer: Writer,
  field field: String,
  value value: Int,
  bits bits: Int,
) -> Writer {
  write_unsigned(writer:, field:, value:, bits:)
}

/// Writes a count of unsigned values in `count_bits` bits, then each in `bits`
/// bits.
pub fn write_unsigned_array(
  writer writer: Writer,
  field field: String,
  items items: List(Int),
  count_bits count_bits: Int,
  bits bits: Int,
) -> Writer {
  write_array(
    writer:,
    field:,
    items:,
    count_bits:,
    write_item: fn(writer, item) {
      write_unsigned(writer:, field:, value: item, bits:)
    },
  )
}

/// Writes unsigned values in `bits` bits each, with no count: the reader takes
/// as many as the list `like` holds, so a list of another length is an error.
pub fn write_unsigned_array_like(
  writer writer: Writer,
  field field: String,
  items items: List(Int),
  like like: List(a),
  bits bits: Int,
) -> Writer {
  let expected = list.length(like)
  let actual = list.length(items)
  use <- bool.guard(
    when: expected != actual,
    return: fail(writer:, error: ItemCountDisagrees(field:, expected:, actual:)),
  )
  list.fold(items, writer, fn(writer, item) {
    write_unsigned(writer:, field:, value: item, bits:)
  })
}

/// Writes a count of 32-bit floats, kept as their bits, in `count_bits` bits,
/// then each in 32 bits.
pub fn write_float32_array(
  writer writer: Writer,
  field field: String,
  items items: List(Int),
  count_bits count_bits: Int,
) -> Writer {
  write_unsigned_array(writer:, field:, items:, count_bits:, bits: 32)
}

/// Writes a count of texts in `count_bits` bits, then each as a wide text.
pub fn write_wide_texts(
  writer writer: Writer,
  field field: String,
  texts texts: List(String),
  count_bits count_bits: Int,
) -> Writer {
  write_array(
    writer:,
    field:,
    items: texts,
    count_bits:,
    write_item: fn(writer, text) { write_wide_text(writer:, field:, text:) },
  )
}

/// A reader at the start of a body.
pub fn new_reader(body: BitArray) -> Reader {
  Reader(bytes: body, position: 0)
}

/// Whether the body ends where the last field did: only the zero bits of the
/// last byte may be left.
pub fn finish_reading(reader: Reader) -> Result(Nil, DecodeError) {
  let left = bit_array.byte_size(reader.bytes) - { reader.position + 7 } / 8
  case left > 0 {
    True -> Error(TrailingBytes(left))
    False -> Ok(Nil)
  }
}

/// Reads an unsigned value of `bits` bits, 1 to 64.
pub fn read_unsigned(
  reader reader: Reader,
  bits bits: Int,
) -> Result(#(Int, Reader), DecodeError) {
  assert bits >= 1 && bits <= 64
    as "a field's width is 1 to 64 bits, and the schema says which"
  let end = reader.position + bits
  let first_byte = reader.position / 8
  let span_bytes = { end + 7 } / 8 - first_byte
  case bit_array.slice(reader.bytes, first_byte, span_bytes) {
    Ok(<<span:size({ span_bytes * 8 })-little>>) -> {
      let shifted = int.bitwise_shift_right(span, reader.position % 8)
      let value = int.bitwise_and(shifted, int.bitwise_shift_left(1, bits) - 1)
      Ok(#(value, Reader(..reader, position: end)))
    }
    _ -> Error(EndOfData)
  }
}

/// Reads the bits of a 32-bit float as the number they are.
pub fn read_float32_bits(
  reader: Reader,
) -> Result(#(Int, Reader), DecodeError) {
  read_unsigned(reader:, bits: 32)
}

/// Reads a wide text written by `write_wide_text`.
pub fn read_wide_text(
  reader: Reader,
) -> Result(#(String, Reader), DecodeError) {
  use #(long, reader) <- result.try(read_unsigned(reader:, bits: 1))
  let count_bits = case long {
    1 -> 15
    _ -> 7
  }
  use #(count, reader) <- result.try(read_unsigned(reader:, bits: count_bits))
  use #(units, reader) <- result.try(read_units(reader:, count:))
  use text <- result.try(from_utf16(units))
  Ok(#(text, reader))
}

/// Reads a counted wide text with at most `max_units` units.
pub fn read_counted_wide_text(
  reader reader: Reader,
  max_units max_units: Int,
) -> Result(#(String, Reader), DecodeError) {
  use #(count, reader) <- result.try(read_unsigned(reader:, bits: 16))
  use <- bool.guard(
    when: count < 1 || count > max_units + 1,
    return: Error(InvalidCountedText),
  )
  use #(units, reader) <- result.try(read_units(reader:, count:))
  use text <- result.try(from_counted_units(units))
  Ok(#(text, reader))
}

/// Reads a GUID: 16 bytes in order.
pub fn read_guid(reader: Reader) -> Result(#(BitArray, Reader), DecodeError) {
  read_raw_bytes(reader:, count: 16)
}

/// Reads `count` raw bytes at the bit position, in order.
pub fn read_raw_bytes(
  reader reader: Reader,
  count count: Int,
) -> Result(#(BitArray, Reader), DecodeError) {
  use <- bool.guard(
    when: reader.position + count * 8 > bit_array.bit_size(reader.bytes),
    return: Error(EndOfData),
  )
  take_bytes(reader:, count:, built: <<>>)
}

/// Reads a server's address in 32 bits and its port in 16.
pub fn read_endpoint(
  reader: Reader,
) -> Result(#(Endpoint, Reader), DecodeError) {
  use #(address, reader) <- result.try(read_unsigned(reader:, bits: 32))
  use #(port, reader) <- result.try(read_unsigned(reader:, bits: 16))
  Ok(#(Endpoint(address:, port:), reader))
}

/// Reads a whole inner frame: moves to the next whole byte, reads the 32-bit
/// length, and takes that many bytes from the start of the length.
pub fn read_whole_frame(
  reader: Reader,
) -> Result(#(BitArray, Reader), DecodeError) {
  let start = { reader.position + 7 } / 8
  let aligned = Reader(..reader, position: start * 8)
  use #(length, _) <- result.try(read_unsigned(reader: aligned, bits: 32))
  use <- bool.guard(when: length < 4, return: Error(InnerFrameTooShort(length)))
  case bit_array.slice(reader.bytes, start, length) {
    Ok(frame) ->
      Ok(#(frame, Reader(..reader, position: { start + length } * 8)))
    Error(Nil) -> Error(EndOfData)
  }
}

/// Reads a count in `count_bits` bits, then that many items through
/// `read_item`.
pub fn read_array(
  reader reader: Reader,
  count_bits count_bits: Int,
  read_item read_item: fn(Reader) -> Result(#(a, Reader), DecodeError),
) -> Result(#(List(a), Reader), DecodeError) {
  use #(count, reader) <- result.try(read_unsigned(reader:, bits: count_bits))
  read_items(reader:, remaining: count, read_item:, built: [])
}

/// Reads an unsigned value of `bits` bits that the schema limits to below
/// `limit`; a value at or above the limit is an error.
pub fn read_unsigned_below(
  reader reader: Reader,
  field field: String,
  bits bits: Int,
  limit limit: Int,
) -> Result(#(Int, Reader), DecodeError) {
  use #(value, reader) <- result.try(read_unsigned(reader:, bits:))
  case value < limit {
    True -> Ok(#(value, reader))
    False -> Error(UnexpectedValue(field:, value:))
  }
}

/// Reads a value the schema fixes, in `bits` bits; any other value is an error.
pub fn read_constant(
  reader reader: Reader,
  field field: String,
  bits bits: Int,
  value value: Int,
) -> Result(Reader, DecodeError) {
  use #(read, reader) <- result.try(read_unsigned(reader:, bits:))
  case read == value {
    True -> Ok(reader)
    False -> Error(UnexpectedValue(field:, value: read))
  }
}

/// Reads a count in `count_bits` bits, then that many unsigned values of `bits`
/// bits each.
pub fn read_unsigned_array(
  reader reader: Reader,
  count_bits count_bits: Int,
  bits bits: Int,
) -> Result(#(List(Int), Reader), DecodeError) {
  read_array(reader:, count_bits:, read_item: fn(reader) {
    read_unsigned(reader:, bits:)
  })
}

/// Reads as many unsigned values of `bits` bits each as the list `like` holds.
pub fn read_unsigned_array_like(
  reader reader: Reader,
  like like: List(a),
  bits bits: Int,
) -> Result(#(List(Int), Reader), DecodeError) {
  read_items(
    reader:,
    remaining: list.length(like),
    read_item: fn(reader) { read_unsigned(reader:, bits:) },
    built: [],
  )
}

/// Reads a count in `count_bits` bits, then that many 32-bit floats as the
/// bits they are.
pub fn read_float32_array(
  reader reader: Reader,
  count_bits count_bits: Int,
) -> Result(#(List(Int), Reader), DecodeError) {
  read_unsigned_array(reader:, count_bits:, bits: 32)
}

/// Reads a count of texts in `count_bits` bits, then that many wide texts.
pub fn read_wide_texts(
  reader reader: Reader,
  count_bits count_bits: Int,
) -> Result(#(List(String), Reader), DecodeError) {
  read_array(reader:, count_bits:, read_item: read_wide_text)
}

fn fail(writer writer: Writer, error error: EncodeError) -> Writer {
  case writer.failure {
    Some(_) -> writer
    None -> Writer(..writer, failure: Some(error))
  }
}

/// Appends the low `bits` bits of a value that is known to fit, least
/// significant bit first, keeping the bits that do not fill a byte for the next
/// write (WriteBits 0x140336380).
fn put(writer writer: Writer, value value: Int, bits bits: Int) -> Writer {
  use <- bool.guard(when: option.is_some(writer.failure), return: writer)
  let combined =
    writer.pending + int.bitwise_shift_left(value, writer.pending_bits)
  let total = writer.pending_bits + bits
  let whole = total / 8
  let low = int.bitwise_and(combined, int.bitwise_shift_left(1, whole * 8) - 1)
  Writer(
    ..writer,
    whole_bytes: <<writer.whole_bytes:bits, low:size({ whole * 8 })-little>>,
    pending: int.bitwise_shift_right(combined, whole * 8),
    pending_bits: total - whole * 8,
  )
}

fn put_units(writer writer: Writer, units units: List(Int)) -> Writer {
  list.fold(units, writer, fn(writer, unit) {
    put(writer:, value: unit, bits: 16)
  })
}

/// Appends bytes in order at the bit position, with no move to a byte boundary
/// (WriteBytesAsBits 0x1403360d0).
fn put_bytes(writer writer: Writer, bytes bytes: BitArray) -> Writer {
  use <- bool.guard(when: option.is_some(writer.failure), return: writer)
  case writer.pending_bits, bytes {
    0, _ ->
      Writer(..writer, whole_bytes: <<writer.whole_bytes:bits, bytes:bits>>)
    _, <<byte, rest:bytes>> ->
      put_bytes(writer: put(writer:, value: byte, bits: 8), bytes: rest)
    _, _ -> writer
  }
}

/// Moves to the next whole byte, the bits left in the last one zero
/// (WriteRawBytes 0x1403365e0).
fn align(writer: Writer) -> Writer {
  case writer.pending_bits {
    0 -> writer
    filled -> put(writer:, value: 0, bits: 8 - filled)
  }
}

/// A text as UTF-16 units: a character above U+FFFF is a high and a low
/// surrogate.
fn utf16_units(text: String) -> List(Int) {
  string.to_utf_codepoints(text)
  |> list.flat_map(fn(codepoint) {
    let value = string.utf_codepoint_to_int(codepoint)
    case value >= 0x10000 {
      True -> {
        let offset = value - 0x10000
        [
          0xD800 + int.bitwise_shift_right(offset, 10),
          0xDC00 + int.bitwise_and(offset, 0x3FF),
        ]
      }
      False -> [value]
    }
  })
}

fn read_units(
  reader reader: Reader,
  count count: Int,
) -> Result(#(List(Int), Reader), DecodeError) {
  read_unit_list(reader:, remaining: count, built: [])
}

fn read_unit_list(
  reader reader: Reader,
  remaining remaining: Int,
  built built: List(Int),
) -> Result(#(List(Int), Reader), DecodeError) {
  case remaining {
    0 -> Ok(#(list.reverse(built), reader))
    _ -> {
      use #(unit, reader) <- result.try(read_unsigned(reader:, bits: 16))
      read_unit_list(reader:, remaining: remaining - 1, built: [unit, ..built])
    }
  }
}

/// The text of a counted text's units: they end in a zero and hold none before
/// it.
fn from_counted_units(units: List(Int)) -> Result(String, DecodeError) {
  case list.reverse(units) {
    [0, ..before] ->
      case list.contains(before, 0) {
        True -> Error(InvalidCountedText)
        False -> from_utf16(list.reverse(before))
      }
    _ -> Error(InvalidCountedText)
  }
}

/// A text from UTF-16 units; a surrogate that is not half of a pair is not a
/// character a string holds.
fn from_utf16(units: List(Int)) -> Result(String, DecodeError) {
  from_utf16_loop(units:, built: [])
}

fn from_utf16_loop(
  units units: List(Int),
  built built: List(UtfCodepoint),
) -> Result(String, DecodeError) {
  case units {
    [] -> Ok(string.from_utf_codepoints(list.reverse(built)))
    [high, low, ..rest]
      if high >= 0xD800 && high <= 0xDBFF && low >= 0xDC00 && low <= 0xDFFF
    ->
      push_codepoint(
        value: 0x10000
          + int.bitwise_shift_left(high - 0xD800, 10)
          + { low - 0xDC00 },
        rest:,
        built:,
      )
    [unit, ..] if unit >= 0xD800 && unit <= 0xDFFF -> Error(InvalidText)
    [unit, ..rest] -> push_codepoint(value: unit, rest:, built:)
  }
}

fn push_codepoint(
  value value: Int,
  rest rest: List(Int),
  built built: List(UtfCodepoint),
) -> Result(String, DecodeError) {
  case string.utf_codepoint(value) {
    Ok(codepoint) -> from_utf16_loop(units: rest, built: [codepoint, ..built])
    Error(Nil) -> Error(InvalidText)
  }
}

/// Takes `count` bytes in order from the bit position, 8 bytes at a time while
/// they last (ReadBytesAsBits 0x140337160).
fn take_bytes(
  reader reader: Reader,
  count count: Int,
  built built: BitArray,
) -> Result(#(BitArray, Reader), DecodeError) {
  case count {
    0 -> Ok(#(built, reader))
    _ if count >= 8 -> {
      use #(word, reader) <- result.try(read_unsigned(reader:, bits: 64))
      take_bytes(reader:, count: count - 8, built: <<
        built:bits,
        word:size(64)-little,
      >>)
    }
    _ -> {
      use #(byte, reader) <- result.try(read_unsigned(reader:, bits: 8))
      take_bytes(reader:, count: count - 1, built: <<built:bits, byte>>)
    }
  }
}

fn read_items(
  reader reader: Reader,
  remaining remaining: Int,
  read_item read_item: fn(Reader) -> Result(#(a, Reader), DecodeError),
  built built: List(a),
) -> Result(#(List(a), Reader), DecodeError) {
  case remaining {
    0 -> Ok(#(list.reverse(built), reader))
    _ -> {
      use #(item, reader) <- result.try(read_item(reader))
      read_items(reader:, remaining: remaining - 1, read_item:, built: [
        item,
        ..built
      ])
    }
  }
}
