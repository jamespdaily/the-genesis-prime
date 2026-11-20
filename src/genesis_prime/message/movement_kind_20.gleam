//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 20, the unit
//// spins: the start yaw, pitch and roll as 32-bit floats, the duration in ms
//// (32 bits), the turn rate in radians a second as a 16-bit half float, a
//// 32-bit time offset in ms and the blend bit. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140c1f070`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind20 {
  MovementKind20(
    yaw: Int,
    pitch: Int,
    roll: Int,
    duration_ms: Int,
    turn_rate: Int,
    time_offset: Int,
    blends: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind20) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 20, 5)
  |> bit_stream.write_float32_bits("yaw", record.yaw)
  |> bit_stream.write_float32_bits("pitch", record.pitch)
  |> bit_stream.write_float32_bits("roll", record.roll)
  |> bit_stream.write_unsigned("duration_ms", record.duration_ms, 32)
  |> bit_stream.write_unsigned("turn_rate", record.turn_rate, 16)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind20, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 20))
  use #(yaw, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(pitch, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(roll, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(duration_ms, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(turn_rate, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind20(
      yaw:,
      pitch:,
      roll:,
      duration_ms:,
      turn_rate:,
      time_offset:,
      blends:,
    ),
    reader,
  ))
}
