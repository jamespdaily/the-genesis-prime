//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00CA (item_charges_changed), server to client: a held item's
//// charges changed: the item's guid and its new charges; the client stores the
//// value as the item's charges, which its use check reads, and raises no
//// event, so no window redraws. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0xca` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00CA

/// The body of message 0x00CA, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemChargesChanged {
  ItemChargesChanged(item_guid: Int, charges: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemChargesChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("item_guid", message.item_guid, 64)
  |> bit_stream.write_unsigned("charges", message.charges, 32)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: ItemChargesChanged) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemChargesChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(charges, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemChargesChanged(item_guid:, charges:))
}
