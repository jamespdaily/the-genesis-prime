//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0814 (spell_threshold_closed), server to client: closes the
//// player's open threshold for a spell: the spell and one bit that starts the
//// cooldowns of the threshold's third spell, or of the spell; the client
//// removes the threshold, so the next press of the ability casts its own
//// spell, and it is the only message that closes a ChargeRelease threshold.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x814` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0814

/// The body of message 0x0814, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellThresholdClosed {
  SpellThresholdClosed(spell4_id: Int, start_cooldowns: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellThresholdClosed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("spell4_id", message.spell4_id, 18)
  |> bit_stream.write_unsigned("start_cooldowns", message.start_cooldowns, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellThresholdClosed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(start_cooldowns, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellThresholdClosed(spell4_id:, start_cooldowns:))
}
