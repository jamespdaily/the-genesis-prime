//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0148 (item_removed), server to client: a held item is gone: the
//// item's guid and the reason; the client empties the slot and raises
//// ItemRemoved, with a further notice for the reason 21, PlayerRequested, and
//// it does not clear the move wait. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x148` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0148

/// The body of message 0x0148, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemRemoved {
  ItemRemoved(item_guid: Int, reason: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemRemoved) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> bit_stream.write_unsigned("reason", message.reason, 6)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemRemoved, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemRemoved(item_guid:, reason:))
}
