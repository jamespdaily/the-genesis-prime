//// Message 0x058F (game_hello_reply), client to server: the first message on a
//// game connection, sent when the server's hello arrives, with the session
//// key. Its fields are listed in `schema.toml` with the client's evidence, and
//// the fact file's `opcode.0x58f` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x058F, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type GameHelloReply {
  GameHelloReply(
    field_1: Int,
    session_key: BitArray,
    field_3: Int,
    account_name: String,
    field_5: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: GameHelloReply) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(GameHelloReply, DecodeError) {
  todo
}
