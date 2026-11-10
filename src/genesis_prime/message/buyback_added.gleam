//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00BA (buyback_added), server to client: one entry added to the
//// end of the player's buyback list; the client keeps no count limit or
//// expiry, and an entry whose Item2 id it does not know is dropped. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0xba` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/buyback_entry.{type BuybackEntry}
import gleam/result

/// The message's number.
pub const message_id = 0x00BA

/// The body of message 0x00BA, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type BuybackAdded {
  BuybackAdded(entry: BuybackEntry)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: BuybackAdded) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> buyback_entry.write(message.entry)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(BuybackAdded, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(entry, reader) <- result.try(buyback_entry.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(BuybackAdded(entry:))
}
