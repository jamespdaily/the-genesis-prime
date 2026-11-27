//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00BD (buyback_removed), server to client: an entry taken off the
//// player's buyback list by its id; the client treats an id it does not hold
//// as an error and changes nothing. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0xbd` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00BD

/// The body of message 0x00BD, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type BuybackRemoved {
  BuybackRemoved(buyback_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: BuybackRemoved) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("buyback_id", message.buyback_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(BuybackRemoved, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(buyback_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(BuybackRemoved(buyback_id:))
}
