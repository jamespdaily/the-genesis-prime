//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a chat format of type 10, a navigation
//// point: a zone id of 14 bits and two floats. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140085ca0`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ChatFormatNavigationPoint {
  ChatFormatNavigationPoint(start: Int, end: Int, zone_id: Int, x: Int, y: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: ChatFormatNavigationPoint,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 10, 4)
  |> bit_stream.write_unsigned("start", record.start, 16)
  |> bit_stream.write_unsigned("end", record.end, 16)
  |> bit_stream.write_unsigned("zone_id", record.zone_id, 14)
  |> bit_stream.write_float32_bits("x", record.x)
  |> bit_stream.write_float32_bits("y", record.y)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(ChatFormatNavigationPoint, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 4, 10))
  use #(start, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(end, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(zone_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  Ok(#(ChatFormatNavigationPoint(start:, end:, zone_id:, x:, y:), reader))
}
