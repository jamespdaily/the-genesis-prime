//// Message 0x07A1 (realm_handoff), server to client: the game server's hand-
//// off to another realm's server: its address, the session key and the realm's
//// name. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x7a1` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{
  type DecodeError, type EncodeError, type Endpoint,
}

/// The body of message 0x07A1, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type RealmHandoff {
  RealmHandoff(
    field_1: Int,
    session_key: BitArray,
    realm_server: Endpoint,
    field_4: Int,
    realm_name: String,
    field_6: Int,
    field_7: Int,
    field_8: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: RealmHandoff) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RealmHandoff, DecodeError) {
  todo
}
