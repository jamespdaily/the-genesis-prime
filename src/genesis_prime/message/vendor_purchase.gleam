//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00BE (vendor_purchase), client to server: the client buys from
//// the open vendor: the unique id of the vendor item (the id 0x90b sent for
//// the item) and the quantity, which counts lots of the item's
//// buyFromVendorStackCount; the client sends it only while the player is
//// alive, under no no-action control state and in a vendor interaction, and
//// checks neither the stock nor the cash. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `opcode.0xbe`
//// names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00BE

/// The body of message 0x00BE, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type VendorPurchase {
  VendorPurchase(unique_id: Int, quantity: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: VendorPurchase) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unique_id", message.unique_id, 32)
  |> bit_stream.write_unsigned("quantity", message.quantity, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(VendorPurchase, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unique_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(quantity, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(VendorPurchase(unique_id:, quantity:))
}
