//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0933 (unit_item_visuals_changed), server to client: some of a
//// unit's item visuals change: the unit and the visuals, each a slot with a
//// display, a colour set and a dye. The client ignores an unknown unit, sets
//// each visual in order and stops at the first it refuses; a display 0 empties
//// the slot (opcode.0x933.empty_display). Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x933` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_visual.{type ItemVisual}
import gleam/result

/// The message's number.
pub const message_id = 0x0933

/// The body of message 0x0933, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitItemVisualsChanged {
  UnitItemVisualsChanged(unit_id: Int, item_visuals: List(ItemVisual))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  message: UnitItemVisualsChanged,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_array(
    "item_visuals",
    message.item_visuals,
    32,
    item_visual.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitItemVisualsChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(item_visuals, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    item_visual.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitItemVisualsChanged(unit_id:, item_visuals:))
}
