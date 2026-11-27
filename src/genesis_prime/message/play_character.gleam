//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07DD (play_character), client to server: the request to play a
//// character, after which the client waits for message 0xAD or 0x162. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x7dd` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x07DD

/// The body of message 0x07DD, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PlayCharacter {
  PlayCharacter(character_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PlayCharacter) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayCharacter, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PlayCharacter(character_id:))
}
