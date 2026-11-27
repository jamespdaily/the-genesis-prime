//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01DA (chat_zone_named), server to client: the WorldZone id every
//// zone-named chat channel is named after: the client keeps it and renames
//// those channels, with no walk to a parent zone. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x1da` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01DA

/// The body of message 0x01DA, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChatZoneNamed {
  ChatZoneNamed(world_zone_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChatZoneNamed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("world_zone_id", message.world_zone_id, 15)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChatZoneNamed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(world_zone_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    15,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChatZoneNamed(world_zone_id:))
}
