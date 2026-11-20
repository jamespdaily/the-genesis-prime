//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 5, the unit
//// moves along one authored spline (a Spline2 row): the spline id in 32 bits,
//// the speed as a 32-bit float, the start position along the spline as a
//// 32-bit float (1.0 is the end), an offset of three 16-bit half floats, a
//// 4-bit walk mode, a 32-bit time offset in ms, the blend bit and two bits the
//// client reads and never uses. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind5 {
  MovementKind5(
    spline_id: Int,
    speed: Int,
    start_position: Int,
    offset_x: Int,
    offset_y: Int,
    offset_z: Int,
    mode: Int,
    time_offset: Int,
    blends: Int,
    unread_11: Int,
    unread_12: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind5) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 5, 5)
  |> bit_stream.write_unsigned("spline_id", record.spline_id, 32)
  |> bit_stream.write_float32_bits("speed", record.speed)
  |> bit_stream.write_float32_bits("start_position", record.start_position)
  |> bit_stream.write_unsigned("offset_x", record.offset_x, 16)
  |> bit_stream.write_unsigned("offset_y", record.offset_y, 16)
  |> bit_stream.write_unsigned("offset_z", record.offset_z, 16)
  |> bit_stream.write_unsigned("mode", record.mode, 4)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
  |> bit_stream.write_unsigned("unread_11", record.unread_11, 1)
  |> bit_stream.write_unsigned("unread_12", record.unread_12, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind5, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 5))
  use #(spline_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(speed, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(start_position, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(offset_x, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(offset_y, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(offset_z, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(mode, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(unread_11, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(unread_12, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind5(
      spline_id:,
      speed:,
      start_position:,
      offset_x:,
      offset_y:,
      offset_z:,
      mode:,
      time_offset:,
      blends:,
      unread_11:,
      unread_12:,
    ),
    reader,
  ))
}
