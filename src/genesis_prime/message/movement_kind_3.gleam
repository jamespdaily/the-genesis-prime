//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 3, whose meaning
//// the client's code does not show: n values of 32 bits (n in 10 bits), n
//// vectors of three 32-bit floats, 2 bits, 32 bits and one bit. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_float_vector.{type MovementFloatVector}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind3 {
  MovementKind3(
    field_2: List(Int),
    field_3: List(MovementFloatVector),
    field_4: Int,
    field_5: Int,
    field_6: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind3) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 3, 5)
  |> bit_stream.write_unsigned_array("field_2", record.field_2, 10, 32)
  |> bit_stream.write_array_like(
    "field_3",
    record.field_3,
    record.field_2,
    movement_float_vector.write,
  )
  |> bit_stream.write_unsigned("field_4", record.field_4, 2)
  |> bit_stream.write_unsigned("field_5", record.field_5, 32)
  |> bit_stream.write_unsigned("field_6", record.field_6, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind3, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 3))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    10,
    32,
  ))
  use #(field_3, reader) <- result.try(bit_stream.read_array_like(
    reader,
    field_2,
    movement_float_vector.read,
  ))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(MovementKind3(field_2:, field_3:, field_4:, field_5:, field_6:), reader))
}
