//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07E0 (character_select_start), client to server: sent when
//// character select starts; its body is empty. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x7e0` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The body of message 0x07E0, which is empty.
pub type CharacterSelectStart {
  CharacterSelectStart
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: CharacterSelectStart) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CharacterSelectStart, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(CharacterSelectStart)
}
