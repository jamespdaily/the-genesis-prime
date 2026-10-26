//// Message 0x00AD (enter_world), server to client: the game server's answer
//// after the player chose a character, with which the client enters the world.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0xad` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x00AD, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type EnterWorld {
  EnterWorld(
    field_1: Int,
    field_2: Int,
    field_3: Int,
    field_4: Int,
    field_5: Int,
    field_6: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: EnterWorld) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(EnterWorld, DecodeError) {
  todo
}
