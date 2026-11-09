//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x03EC (own_commodity_orders_request), client to server: the client
//// asks for the player's own commodity orders, with an empty body. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x3ec` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x03EC

/// The body of message 0x03EC, which is empty.
pub type OwnCommodityOrdersRequest {
  OwnCommodityOrdersRequest
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  _message: OwnCommodityOrdersRequest,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(
  body: BitArray,
) -> Result(OwnCommodityOrdersRequest, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(OwnCommodityOrdersRequest)
}
