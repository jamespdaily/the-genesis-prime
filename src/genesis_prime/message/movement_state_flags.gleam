//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 24, the unit's
//// movement state flags in 32 bits. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `0x140c1f070` names the
//// record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementStateFlags {
  MovementStateFlags(flags: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: MovementStateFlags,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 24, 5)
  |> bit_stream.write_unsigned("flags", record.flags, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementStateFlags, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 24))
  use #(flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(MovementStateFlags(flags:), reader))
}
