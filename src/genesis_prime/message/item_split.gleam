//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x017D (item_split), client to server: the client splits a stack:
//// the guid of the stack, the empty place the new stack goes to and the count
//// to take off, which the client sends as a move instead when it is the
//// stack's whole count; the client sets no wait for it. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x17d` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_place.{type ItemPlace}
import gleam/result

/// The message's number.
pub const message_id = 0x017D

/// The body of message 0x017D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemSplit {
  ItemSplit(item_guid: Int, to: ItemPlace, count: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemSplit) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> item_place.write(message.to)
  |> bit_stream.write_unsigned("count", message.count, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemSplit, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(to, reader) <- result.try(item_place.read(reader))
  use #(count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemSplit(item_guid:, to:, count:))
}
