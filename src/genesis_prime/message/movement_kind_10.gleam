//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 10, whose
//// meaning the client's code does not show: one bit. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140c1f070`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind10 {
  MovementKind10(field_2: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind10) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 10, 5)
  |> bit_stream.write_unsigned("field_2", record.field_2, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind10, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 10))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(MovementKind10(field_2:), reader))
}
