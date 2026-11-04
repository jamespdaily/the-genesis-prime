//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one entry of the ability book's tiers: the
//// Spell4Base id, the tier (0 counts as 1) and the action set index. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x1a0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type AbilityTier {
  AbilityTier(spell4_base_id: Int, tier: Int, action_set_index: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: AbilityTier) -> Writer {
  writer
  |> bit_stream.write_unsigned("spell4_base_id", record.spell4_base_id, 18)
  |> bit_stream.write_unsigned("tier", record.tier, 4)
  |> bit_stream.write_unsigned("action_set_index", record.action_set_index, 3)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(AbilityTier, Reader), DecodeError) {
  use #(spell4_base_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(tier, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(action_set_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    3,
  ))
  Ok(#(AbilityTier(spell4_base_id:, tier:, action_set_index:), reader))
}
