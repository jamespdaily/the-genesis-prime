//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0166 (vendor_sale), client to server: the client sells to the
//// open vendor the item at a place, a quantity of it (a quantity below the
//// stack's count sells part of the stack); the client checks the quantity, the
//// item, the player and the vendor before sending. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x166` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_place.{type ItemPlace}
import gleam/result

/// The message's number.
pub const message_id = 0x0166

/// The body of message 0x0166, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type VendorSale {
  VendorSale(place: ItemPlace, quantity: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: VendorSale) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> item_place.write(message.place)
  |> bit_stream.write_unsigned("quantity", message.quantity, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(VendorSale, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(place, reader) <- result.try(item_place.read(reader))
  use #(quantity, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(VendorSale(place:, quantity:))
}
