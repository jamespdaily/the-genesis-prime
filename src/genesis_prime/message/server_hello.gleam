//// Message 0x0003 (server_hello), server to client: the hello every server
//// sends on a new connection, with the build and the message table checksum
//// the client checks. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x3` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The body of message 0x0003, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type ServerHello {
  ServerHello(
    build: Int,
    field_2: Int,
    field_3: Int,
    field_4: Int,
    field_5: Int,
    field_6: Int,
    field_7: Int,
    message_table_checksum: Int,
    field_9: Int,
    field_10: Int,
    field_11: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ServerHello) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ServerHello, DecodeError) {
  todo
}
