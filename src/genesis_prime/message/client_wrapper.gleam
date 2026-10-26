//// Message 0x0244 (client_wrapper), client to server: the wrapper every
//// message the client sends travels in, holding one whole inner frame. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x244` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x0244, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type ClientWrapper {
  ClientWrapper(inner_frame: BitArray)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ClientWrapper) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientWrapper, DecodeError) {
  todo
}
