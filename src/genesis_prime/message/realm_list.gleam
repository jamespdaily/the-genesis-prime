//// Message 0x0761 (realm_list), server to client: the realm list the client
//// shows during realm select, with the realms and their text groups. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x761` names the message.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/realm_entry.{type RealmEntry}
import genesis_prime/message/text_group.{type TextGroup}

/// The body of message 0x0761, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type RealmList {
  RealmList(
    field_1: Int,
    realms: List(RealmEntry),
    text_groups: List(TextGroup),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: RealmList) -> Result(BitArray, EncodeError) {
  todo
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RealmList, DecodeError) {
  todo
}
