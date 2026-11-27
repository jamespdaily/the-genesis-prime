//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0811 (spell_targets_removed), server to client: a cast is taken
//// off some units: the cast id and the units; the client finds the cast (an
//// unknown id drops the message) and destroys its target node on each unit it
//// holds, which ends every effect the cast holds there and the unit's buff for
//// the spell, and destroys the cast too when it has no target left and its
//// cast method is not Channeled, ChanneledField, Multiphase or 10. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x811` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0811

/// The body of message 0x0811, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellTargetsRemoved {
  SpellTargetsRemoved(cast_id: Int, unit_ids: List(Int))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellTargetsRemoved) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned_array("unit_ids", message.unit_ids, 32, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellTargetsRemoved, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unit_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    32,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellTargetsRemoved(cast_id:, unit_ids:))
}
