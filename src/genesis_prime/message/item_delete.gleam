//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0149 (item_delete), client to server: the client destroys the
//// held item at a place; the client refuses before sending when there is no
//// Item2 row or the item cannot be deleted, sends nothing for a worn bag or an
//// item in a trade, and sets no wait for it. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x149` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_place.{type ItemPlace}
import gleam/result

/// The message's number.
pub const message_id = 0x0149

/// The body of message 0x0149, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemDelete {
  ItemDelete(place: ItemPlace)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemDelete) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> item_place.write(message.place)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemDelete, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(place, reader) <- result.try(item_place.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemDelete(place:))
}
