//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 1, the unit the
//// player stands on, 0 for none. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementPlatform {
  MovementPlatform(unit_id: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementPlatform) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 1, 5)
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementPlatform, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 1))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(MovementPlatform(unit_id:), reader))
}
