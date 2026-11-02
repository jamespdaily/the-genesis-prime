//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 6, whose meaning
//// the client's code does not show: n values of 32 bits (n in 10 bits), 16
//// bits, three 32-bit floats, three values of 16 bits, 4 bits, two values of
//// 32 bits and two single bits. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind6 {
  MovementKind6(
    field_2: List(Int),
    field_3: Int,
    field_4: Int,
    field_5: Int,
    field_6: Int,
    field_7: Int,
    field_8: Int,
    field_9: Int,
    field_10: Int,
    field_11: Int,
    field_12: Int,
    field_13: Int,
    field_14: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind6) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 6, 5)
  |> bit_stream.write_unsigned_array("field_2", record.field_2, 10, 32)
  |> bit_stream.write_unsigned("field_3", record.field_3, 16)
  |> bit_stream.write_float32_bits("field_4", record.field_4)
  |> bit_stream.write_float32_bits("field_5", record.field_5)
  |> bit_stream.write_float32_bits("field_6", record.field_6)
  |> bit_stream.write_unsigned("field_7", record.field_7, 16)
  |> bit_stream.write_unsigned("field_8", record.field_8, 16)
  |> bit_stream.write_unsigned("field_9", record.field_9, 16)
  |> bit_stream.write_unsigned("field_10", record.field_10, 4)
  |> bit_stream.write_unsigned("field_11", record.field_11, 32)
  |> bit_stream.write_unsigned("field_12", record.field_12, 32)
  |> bit_stream.write_unsigned("field_13", record.field_13, 1)
  |> bit_stream.write_unsigned("field_14", record.field_14, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind6, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 6))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    10,
    32,
  ))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_6, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(field_11, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_12, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_13, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind6(
      field_2:,
      field_3:,
      field_4:,
      field_5:,
      field_6:,
      field_7:,
      field_8:,
      field_9:,
      field_10:,
      field_11:,
      field_12:,
      field_13:,
      field_14:,
    ),
    reader,
  ))
}
