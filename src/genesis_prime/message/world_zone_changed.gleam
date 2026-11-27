//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x063A (world_zone_changed), client to server: the WorldZone id the
//// player unit stands in has changed, the most specific zone the terrain
//// names, not rolled up to a parent: the old and the new id. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x63a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x063A

/// The body of message 0x063A, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type WorldZoneChanged {
  WorldZoneChanged(old_world_zone_id: Int, new_world_zone_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WorldZoneChanged) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "old_world_zone_id",
    message.old_world_zone_id,
    15,
  )
  |> bit_stream.write_unsigned(
    "new_world_zone_id",
    message.new_world_zone_id,
    15,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WorldZoneChanged, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(old_world_zone_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    15,
  ))
  use #(new_world_zone_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    15,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WorldZoneChanged(old_world_zone_id:, new_world_zone_id:))
}
