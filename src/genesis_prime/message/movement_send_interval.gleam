//// Message 0x00F1 (movement_send_interval), server to client: sets the
//// interval at which the client sends the player's movement commands. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0xf1` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x00F1, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type MovementSendInterval {
  MovementSendInterval(
    field_1: Int,
    field_2: Int,
    field_3: Int,
    interval_milliseconds: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: MovementSendInterval) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(MovementSendInterval, DecodeError) {
  todo
}
