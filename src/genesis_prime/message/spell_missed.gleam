//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07FB (spell_missed), server to client: some of a cast's targets
//// were missed: the cast id and, for each, the target unit, a 4-bit reason and
//// a time in milliseconds; the client finds the cast (an unknown id drops the
//// message) and, for reason 0 with the player the caster or the target, raises
//// AttackMissed, which it shows over the target as Deflect. A description with
//// combat result 0 raises no floater, so this is how a deflect is shown. Gap:
//// what any other reason means is not read. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x7fb` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/spell_miss.{type SpellMiss}
import gleam/result

/// The message's number.
pub const message_id = 0x07FB

/// The body of message 0x07FB, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellMissed {
  SpellMissed(cast_id: Int, misses: List(SpellMiss))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellMissed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_array("misses", message.misses, 32, spell_miss.write)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellMissed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(misses, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    spell_miss.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellMissed(cast_id:, misses:))
}
