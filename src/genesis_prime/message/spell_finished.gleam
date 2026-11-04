//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07FE (spell_finished), server to client: a cast ends: the cast
//// id; the client drops an unknown id, and a Channeled cast starts its
//// cooldowns here. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x7fe` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x07FE

/// The body of message 0x07FE, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellFinished {
  SpellFinished(cast_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellFinished) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellFinished, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellFinished(cast_id:))
}
