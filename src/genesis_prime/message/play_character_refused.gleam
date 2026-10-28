//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0162 (play_character_refused), server to client: the answer that
//// playing the chosen character failed. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x162` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/play_refusal.{type PlayRefusal}
import gleam/result

/// The message's number.
pub const message_id = 0x0162

/// The body of message 0x0162, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PlayCharacterRefused {
  PlayCharacterRefused(result: PlayRefusal)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PlayCharacterRefused) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "result",
    play_refusal.to_value(message.result),
    3,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayCharacterRefused, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  let result = play_refusal.from_value(result)
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PlayCharacterRefused(result:))
}
