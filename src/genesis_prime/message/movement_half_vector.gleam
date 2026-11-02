//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one vector of a movement command's list:
//// three values of 16 bits. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementHalfVector {
  MovementHalfVector(field_1: Int, field_2: Int, field_3: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: MovementHalfVector,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("field_1", record.field_1, 16)
  |> bit_stream.write_unsigned("field_2", record.field_2, 16)
  |> bit_stream.write_unsigned("field_3", record.field_3, 16)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementHalfVector, Reader), DecodeError) {
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  Ok(#(MovementHalfVector(field_1:, field_2:, field_3:), reader))
}
