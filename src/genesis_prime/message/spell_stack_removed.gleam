//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0813 (spell_stack_removed), server to client: one stack fewer of
//// a cast on a unit: the cast id and the unit; the client finds the cast and
//// its target node on the unit (either missing drops the message), lowers the
//// node's instance count by 1, and the unit's buff for the spell loses one
//// stack and goes at 0; the cast's effects on the unit stay. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x813` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0813

/// The body of message 0x0813, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellStackRemoved {
  SpellStackRemoved(cast_id: Int, unit_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellStackRemoved) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellStackRemoved, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellStackRemoved(cast_id:, unit_id:))
}
