//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0567 (item_flags_changed), server to client: a held item's flags
//// byte changed: the item's guid and the whole new byte (bit 0 soulbound, bit
//// 3 no refund); the client stores the byte as the item's flags, which its
//// tooltip and its equip confirm read, and raises no event, so no open window
//// redraws. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x567` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0567

/// The body of message 0x0567, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemFlagsChanged {
  ItemFlagsChanged(item_guid: Int, item_flags: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemFlagsChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> bit_stream.write_unsigned("item_flags", message.item_flags, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemFlagsChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(item_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemFlagsChanged(item_guid:, item_flags:))
}
