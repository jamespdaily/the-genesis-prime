//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 14, the unit's
//// rotation in radians: yaw, pitch and roll as 32-bit floats, and a bit that
//// places the rotation at once when 0 and blends it into the last rotation
//// segment when 1. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementRotation {
  MovementRotation(yaw: Int, pitch: Int, roll: Int, blends: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementRotation) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 14, 5)
  |> bit_stream.write_float32_bits("yaw", record.yaw)
  |> bit_stream.write_float32_bits("pitch", record.pitch)
  |> bit_stream.write_float32_bits("roll", record.roll)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementRotation, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 14))
  use #(yaw, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(pitch, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(roll, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(MovementRotation(yaw:, pitch:, roll:, blends:), reader))
}
