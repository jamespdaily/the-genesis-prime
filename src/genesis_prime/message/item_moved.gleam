//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0569 (item_moved), server to client: a held item moved to an
//// empty place: the item's guid and its new place as one 64-bit value, bag
//// index in bits 0 to 7 and location in bits 8 to 15; the client files the
//// item at the place, empties its old slot and clears its move wait, and moves
//// no item already at the place, so a swap is message 0x568. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x569` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0569

/// The body of message 0x0569, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemMoved {
  ItemMoved(item_guid: Int, place: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemMoved) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> bit_stream.write_unsigned("place", message.place, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemMoved, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(place, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemMoved(item_guid:, place:))
}
