//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: an effect result of tag 0: one bit, which
//// the client does not read. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `0x140094890` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellEffectBit {
  SpellEffectBit(field_2: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellEffectBit) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 0, 2)
  |> bit_stream.write_unsigned("field_2", record.field_2, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SpellEffectBit, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 2, 0))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(SpellEffectBit(field_2:), reader))
}
