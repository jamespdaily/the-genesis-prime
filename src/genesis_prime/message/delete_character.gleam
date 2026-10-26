//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0352 (delete_character), client to server: the request to delete
//// a character, after which the client waits for message 0xE6. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x352` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0352

/// The body of message 0x0352, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type DeleteCharacter {
  DeleteCharacter(character_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: DeleteCharacter) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(DeleteCharacter, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(DeleteCharacter(character_id:))
}
