//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07FC (spell_cast_refused), server to client: refuses the player's
//// cast: the client's own id for the cast, the Spell4 id and the result, which
//// the client shows as a cast failure for that spell; it drops the pending
//// cast and clears the global cooldown. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x7fc` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/cast_result.{type CastResult}
import gleam/result

/// The message's number.
pub const message_id = 0x07FC

/// The body of message 0x07FC, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellCastRefused {
  SpellCastRefused(client_cast_id: Int, spell4_id: Int, result: CastResult)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellCastRefused) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_cast_id", message.client_cast_id, 32)
  |> bit_stream.write_unsigned("spell4_id", message.spell4_id, 18)
  |> bit_stream.write_unsigned(
    "result",
    cast_result.to_value(message.result),
    9,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellCastRefused, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  let result = cast_result.from_value(result)
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellCastRefused(client_cast_id:, spell4_id:, result:))
}
