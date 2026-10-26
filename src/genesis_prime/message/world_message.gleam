//// Message 0x038C (world_message), client to server: carries one world message
//// from the client, as a 5-bit value and the world message's whole frame. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x38c` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x038C, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type WorldMessage {
  WorldMessage(field_1: Int, inner_frame: BitArray)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WorldMessage) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WorldMessage, DecodeError) {
  todo
}
