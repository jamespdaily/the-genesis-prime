//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x083C (world_loading_screen_shown), server to client: shows the
//// loading screen of the world the player is already in for about a second,
//// without leaving the world or removing any unit; its body is empty. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x83c` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x083C

/// The body of message 0x083C, which is empty.
pub type WorldLoadingScreenShown {
  WorldLoadingScreenShown
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  _message: WorldLoadingScreenShown,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WorldLoadingScreenShown, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(WorldLoadingScreenShown)
}
