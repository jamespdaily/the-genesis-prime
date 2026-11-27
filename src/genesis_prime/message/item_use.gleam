//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0943 (item_use), client to server: the client casts the spell of
//// a used item: its own id for the cast, the place of the used item, the
//// target unit id (0 for none), a second item place (location 300 and index
//// 0xffffffff unless the item is used on another item) and the placed
//// position, which the client reads only for a ground spell; the spell is not
//// sent, the item names it. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x943` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_place.{type ItemPlace}
import gleam/result

/// The message's number.
pub const message_id = 0x0943

/// The body of message 0x0943, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ItemUse {
  ItemUse(
    client_cast_id: Int,
    item: ItemPlace,
    target_unit_id: Int,
    second_item: ItemPlace,
    position_x: Int,
    position_y: Int,
    position_z: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ItemUse) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_cast_id", message.client_cast_id, 32)
  |> item_place.write(message.item)
  |> bit_stream.write_unsigned("target_unit_id", message.target_unit_id, 32)
  |> item_place.write(message.second_item)
  |> bit_stream.write_float32_bits("position_x", message.position_x)
  |> bit_stream.write_float32_bits("position_y", message.position_y)
  |> bit_stream.write_float32_bits("position_z", message.position_z)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ItemUse, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(item, reader) <- result.try(item_place.read(reader))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(second_item, reader) <- result.try(item_place.read(reader))
  use #(position_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ItemUse(
    client_cast_id:,
    item:,
    target_unit_id:,
    second_item:,
    position_x:,
    position_y:,
    position_z:,
  ))
}
