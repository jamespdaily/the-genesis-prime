//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0816 (spell_threshold_opened), server to client: opens a
//// threshold for one of the player's spells at index 0: the spell, the second
//// spell that a press is resolved through, the third spell whose cooldowns
//// start when a RapidTap threshold ends (0 is the opened spell) and a 32-bit
//// value the client sends back as the cast id of a 0x801 when a ChargeRelease
//// cast ends without its release. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x816` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0816

/// The body of message 0x0816, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellThresholdOpened {
  SpellThresholdOpened(
    spell4_id: Int,
    resolving_spell4_id: Int,
    cooldown_spell4_id: Int,
    cancel_cast_id: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellThresholdOpened) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("spell4_id", message.spell4_id, 18)
  |> bit_stream.write_unsigned(
    "resolving_spell4_id",
    message.resolving_spell4_id,
    18,
  )
  |> bit_stream.write_unsigned(
    "cooldown_spell4_id",
    message.cooldown_spell4_id,
    18,
  )
  |> bit_stream.write_unsigned("cancel_cast_id", message.cancel_cast_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellThresholdOpened, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(resolving_spell4_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(cooldown_spell4_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(cancel_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellThresholdOpened(
    spell4_id:,
    resolving_spell4_id:,
    cooldown_spell4_id:,
    cancel_cast_id:,
  ))
}
