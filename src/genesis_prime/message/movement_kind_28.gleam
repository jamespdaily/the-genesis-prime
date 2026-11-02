//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 28, whose
//// meaning the client's code does not show: n values of 32 bits (n in 8 bits),
//// n more values of 32 bits and one value of 32 bits. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140c1f070`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind28 {
  MovementKind28(field_2: List(Int), field_3: List(Int), field_4: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind28) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 28, 5)
  |> bit_stream.write_unsigned_array("field_2", record.field_2, 8, 32)
  |> bit_stream.write_unsigned_array_like(
    "field_3",
    record.field_3,
    record.field_2,
    32,
  )
  |> bit_stream.write_unsigned("field_4", record.field_4, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind28, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 28))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    8,
    32,
  ))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned_array_like(
    reader,
    field_2,
    32,
  ))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(MovementKind28(field_2:, field_3:, field_4:), reader))
}
