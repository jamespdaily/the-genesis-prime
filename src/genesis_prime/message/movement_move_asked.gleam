//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 11, the move the
//// player asks for: three 16-bit half floats and one bit. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementMoveAsked {
  MovementMoveAsked(
    x: Int,
    y: Int,
    z: Int,
    /// Safe by `opcode.0x637`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_5: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: MovementMoveAsked,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 11, 5)
  |> bit_stream.write_unsigned("x", record.x, 16)
  |> bit_stream.write_unsigned("y", record.y, 16)
  |> bit_stream.write_unsigned("z", record.z, 16)
  |> bit_stream.write_unsigned("field_5", record.field_5, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementMoveAsked, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 11))
  use #(x, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(y, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(z, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(MovementMoveAsked(x:, y:, z:, field_5:), reader))
}
