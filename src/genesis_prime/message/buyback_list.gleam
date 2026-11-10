//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00BC (buyback_list), server to client: the player's whole buyback
//// list: the entries replace the list the client holds, and an empty list
//// clears the Buyback tab. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0xbc` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/buyback_entry.{type BuybackEntry}
import gleam/result

/// The message's number.
pub const message_id = 0x00BC

/// The body of message 0x00BC, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type BuybackList {
  BuybackList(entries: List(BuybackEntry))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: BuybackList) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_array("entries", message.entries, 32, buyback_entry.write)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(BuybackList, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(entries, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    buyback_entry.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(BuybackList(entries:))
}
