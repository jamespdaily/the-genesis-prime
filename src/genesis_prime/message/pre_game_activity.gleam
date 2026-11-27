//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0241 (pre_game_activity), client to server: the client's activity
//// signal on its realm-select or character-select connection, with an empty
//// body, sent once 60 seconds have passed and the player has used the keyboard
//// or mouse in the last 60 seconds. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x241` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0241

/// The body of message 0x0241, which is empty.
pub type PreGameActivity {
  PreGameActivity
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: PreGameActivity) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PreGameActivity, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(PreGameActivity)
}
