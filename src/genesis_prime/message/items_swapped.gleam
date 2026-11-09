//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0568 (items_swapped), server to client: two held items swapped:
//// each item's guid and its new place as one 64-bit value, as message 0x569
//// carries them (the moved item at the destination, then the other item at the
//// source); the client empties both old slots, files each item at its place
//// and clears its move wait. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x568` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0568

/// The body of message 0x0568, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemsSwapped {
  ItemsSwapped(
    first_guid: Int,
    first_place: Int,
    second_guid: Int,
    second_place: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemsSwapped) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("first_guid", message.first_guid, 64)
  |> bit_stream.write_unsigned("first_place", message.first_place, 64)
  |> bit_stream.write_unsigned("second_guid", message.second_guid, 64)
  |> bit_stream.write_unsigned("second_place", message.second_place, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemsSwapped, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(first_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(first_place, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(second_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(second_place, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemsSwapped(first_guid:, first_place:, second_guid:, second_place:))
}
