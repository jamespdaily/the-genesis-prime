//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0182 (item_move), client to server: the client moves a held item:
//// the place it leaves and the place it goes to; moves, swaps, equips and
//// unequips are all this message, and a swap is a move onto an occupied slot.
//// The client sends one at a time and refuses the others for 10 seconds, until
//// 0x569, 0x568, 0x56A or 0x17F clears the wait. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x182` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_place.{type ItemPlace}
import gleam/result

/// The message's number.
pub const message_id = 0x0182

/// The body of message 0x0182, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemMove {
  ItemMove(from: ItemPlace, to: ItemPlace)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemMove) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> item_place.write(message.from)
  |> item_place.write(message.to)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemMove, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(from, reader) <- result.try(item_place.read(reader))
  use #(to, reader) <- result.try(item_place.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemMove(from:, to:))
}
