//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 16, the unit's
//// rotation follows an authored spline's orientation: the spline id in 32
//// bits, the speed as a 16-bit half float, the start position along the spline
//// as a 32-bit float, a 4-bit walk mode, a 32-bit time offset in ms, the blend
//// bit and one bit the client reads and never uses. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140c1f070`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind16 {
  MovementKind16(
    spline_id: Int,
    speed: Int,
    start_position: Int,
    mode: Int,
    time_offset: Int,
    blends: Int,
    unread_8: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind16) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 16, 5)
  |> bit_stream.write_unsigned("spline_id", record.spline_id, 32)
  |> bit_stream.write_unsigned("speed", record.speed, 16)
  |> bit_stream.write_float32_bits("start_position", record.start_position)
  |> bit_stream.write_unsigned("mode", record.mode, 4)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
  |> bit_stream.write_unsigned("unread_8", record.unread_8, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind16, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 16))
  use #(spline_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(speed, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(start_position, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(mode, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(unread_8, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind16(
      spline_id:,
      speed:,
      start_position:,
      mode:,
      time_offset:,
      blends:,
      unread_8:,
    ),
    reader,
  ))
}
