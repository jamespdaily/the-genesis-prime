//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00BB (vendor_buyback), client to server: the client buys back an
//// entry of its Buyback tab: the buyback id the entry was added with (0xBA,
//// 0xBC); the client sends it under the conditions of a buy (a vendor
//// interaction, alive, no no-action control state) and checks nothing of the
//// list or the cash. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xbb` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00BB

/// The body of message 0x00BB, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type VendorBuyback {
  VendorBuyback(buyback_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: VendorBuyback) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("buyback_id", message.buyback_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(VendorBuyback, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(buyback_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(VendorBuyback(buyback_id:))
}
