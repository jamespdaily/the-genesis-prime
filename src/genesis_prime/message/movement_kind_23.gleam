//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 23, timed scale
//// keys: the times (32 bits each, a count in 8 bits), a scale as a 16-bit half
//// float for each time, the path type in 2 bits (0 straight lines, 1 a curve),
//// a 32-bit time offset in ms and the blend bit. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140c1f070`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind23 {
  MovementKind23(
    times: List(Int),
    scales: List(Int),
    path_type: Int,
    time_offset: Int,
    blends: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind23) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 23, 5)
  |> bit_stream.write_unsigned_array("times", record.times, 8, 32)
  |> bit_stream.write_unsigned_array_like(
    "scales",
    record.scales,
    record.times,
    16,
  )
  |> bit_stream.write_unsigned("path_type", record.path_type, 2)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind23, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 23))
  use #(times, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    8,
    32,
  ))
  use #(scales, reader) <- result.try(bit_stream.read_unsigned_array_like(
    reader,
    times,
    16,
  ))
  use #(path_type, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind23(times:, scales:, path_type:, time_offset:, blends:),
    reader,
  ))
}
