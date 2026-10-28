//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one movement command of a new unit, of kind
//// 2: the position, which the unit is placed at at once when the last bit is 0
//// and blends onto its last segment when it is 1. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x1400ad350`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitPositionCommand {
  UnitPositionCommand(x: Int, y: Int, z: Int, blends: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: UnitPositionCommand,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 2, 5)
  |> bit_stream.write_float32_bits("x", record.x)
  |> bit_stream.write_float32_bits("y", record.y)
  |> bit_stream.write_float32_bits("z", record.z)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(UnitPositionCommand, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 2))
  use #(x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(UnitPositionCommand(x:, y:, z:, blends:), reader))
}
