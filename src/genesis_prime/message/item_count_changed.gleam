//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x017F (item_count_changed), server to client: a held item's stack
//// count changed: the item's guid, the new count and the reason; the client
//// sets the count, clears its move wait, and raises ItemRemoved for a drop or
//// its gain events for a rise (reason 0, StackSplit, raises no further
//// notice). Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x17f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x017F

/// The body of message 0x017F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemCountChanged {
  ItemCountChanged(item_guid: Int, count: Int, reason: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemCountChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> bit_stream.write_unsigned("count", message.count, 32)
  |> bit_stream.write_unsigned("reason", message.reason, 6)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemCountChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemCountChanged(item_guid:, count:, reason:))
}
