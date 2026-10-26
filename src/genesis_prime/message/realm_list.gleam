//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0761 (realm_list), server to client: the realm list the client
//// shows during realm select, with the realms and their text groups. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x761` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/realm_entry.{type RealmEntry}
import genesis_prime/message/text_group.{type TextGroup}
import gleam/result

/// The message's number.
pub const message_id = 0x0761

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
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 64)
  |> bit_stream.write_array("realms", message.realms, 32, realm_entry.write)
  |> bit_stream.write_array(
    "text_groups",
    message.text_groups,
    32,
    text_group.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RealmList, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(realms, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    realm_entry.read,
  ))
  use #(text_groups, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    text_group.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(RealmList(field_1:, realms:, text_groups:))
}
