//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one tier edit of the ability builder's
//// save: the Spell4Base id and the tier the window edited it to. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0xb1` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ActionSetTierChange {
  ActionSetTierChange(spell4_base_id: Int, tier: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: ActionSetTierChange,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("spell4_base_id", record.spell4_base_id, 18)
  |> bit_stream.write_unsigned("tier", record.tier, 8)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(ActionSetTierChange, Reader), DecodeError) {
  use #(spell4_base_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(tier, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  Ok(#(ActionSetTierChange(spell4_base_id:, tier:), reader))
}
