//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 18, which turns
//// the unit to face another unit and keeps it facing that unit: the unit's id
//// as 32 bits, and a bit that turns at once when 0 and over half a second when
//// 1. Its fields are listed in `schema.toml` with the client's evidence, and
//// the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementFaceUnit {
  MovementFaceUnit(unit_id: Int, blends: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementFaceUnit) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 18, 5)
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementFaceUnit, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 18))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(MovementFaceUnit(unit_id:, blends:), reader))
}
