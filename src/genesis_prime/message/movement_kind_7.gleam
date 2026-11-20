//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 7, a ballistic
//// arc to a point: the end point and the start point (three 32-bit floats
//// each), the flight time in ms (32 bits), the gravity as a 32-bit float, a
//// 32-bit time offset in ms that shortens the flight, and the blend bit. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind7 {
  MovementKind7(
    end_x: Int,
    end_y: Int,
    end_z: Int,
    start_x: Int,
    start_y: Int,
    start_z: Int,
    flight_time_ms: Int,
    gravity: Int,
    time_offset: Int,
    blends: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind7) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 7, 5)
  |> bit_stream.write_float32_bits("end_x", record.end_x)
  |> bit_stream.write_float32_bits("end_y", record.end_y)
  |> bit_stream.write_float32_bits("end_z", record.end_z)
  |> bit_stream.write_float32_bits("start_x", record.start_x)
  |> bit_stream.write_float32_bits("start_y", record.start_y)
  |> bit_stream.write_float32_bits("start_z", record.start_z)
  |> bit_stream.write_unsigned("flight_time_ms", record.flight_time_ms, 32)
  |> bit_stream.write_float32_bits("gravity", record.gravity)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind7, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 7))
  use #(end_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(end_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(end_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(start_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(start_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(start_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(flight_time_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(gravity, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind7(
      end_x:,
      end_y:,
      end_z:,
      start_x:,
      start_y:,
      start_z:,
      flight_time_ms:,
      gravity:,
      time_offset:,
      blends:,
    ),
    reader,
  ))
}
