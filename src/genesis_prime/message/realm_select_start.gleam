//// Message 0x07A4 (realm_select_start), client to server: sent when realm
//// select starts; its body is empty. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x7a4` names the
//// message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x07A4, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type RealmSelectStart {
  RealmSelectStart
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: RealmSelectStart) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RealmSelectStart, DecodeError) {
  todo
}
