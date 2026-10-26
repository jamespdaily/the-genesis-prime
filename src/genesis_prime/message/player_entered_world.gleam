//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0061 (player_entered_world), server to client: tells the client
//// the player has entered the world, which the end of loading waits for; its
//// body is empty. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x61` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0061

/// The body of message 0x0061, which is empty.
pub type PlayerEnteredWorld {
  PlayerEnteredWorld
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: PlayerEnteredWorld) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayerEnteredWorld, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(PlayerEnteredWorld)
}
