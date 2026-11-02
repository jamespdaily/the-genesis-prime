//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 19, whose
//// meaning the client's code does not show: three 32-bit floats and one bit.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind19 {
  MovementKind19(field_2: Int, field_3: Int, field_4: Int, field_5: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind19) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 19, 5)
  |> bit_stream.write_float32_bits("field_2", record.field_2)
  |> bit_stream.write_float32_bits("field_3", record.field_3)
  |> bit_stream.write_float32_bits("field_4", record.field_4)
  |> bit_stream.write_unsigned("field_5", record.field_5, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind19, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 19))
  use #(field_2, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_3, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(MovementKind19(field_2:, field_3:, field_4:, field_5:), reader))
}
