//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one vector of a movement command's list:
//// three 32-bit floats, which kind 4 names x, y and z as the points of its
//// path. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementFloatVector {
  MovementFloatVector(x: Int, y: Int, z: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: MovementFloatVector,
) -> Writer {
  writer
  |> bit_stream.write_float32_bits("x", record.x)
  |> bit_stream.write_float32_bits("y", record.y)
  |> bit_stream.write_float32_bits("z", record.z)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementFloatVector, Reader), DecodeError) {
  use #(x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  Ok(#(MovementFloatVector(x:, y:, z:), reader))
}
