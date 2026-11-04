//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0111 (item_added), server to client: adds an item the player
//// holds; an item at location 4 is an ability, whose item id is its Spell4Base
//// id and whose bag index is the slot a press names, and the client adds the
//// base to the ability book; the reason is 6 bits, and 49 adds without raising
//// the book's change. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x111.ability_bag` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/shared_item.{type SharedItem}
import gleam/result

/// The message's number.
pub const message_id = 0x0111

/// The body of message 0x0111, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemAdded {
  ItemAdded(item: SharedItem, reason: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemAdded) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> shared_item.write(message.item)
  |> bit_stream.write_unsigned("reason", message.reason, 6)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemAdded, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(item, reader) <- result.try(shared_item.read(reader))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemAdded(item:, reason:))
}
