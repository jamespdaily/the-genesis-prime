//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0355 (unit_destroyed), server to client: removes a unit from the
//// world: the unit id and a bit the client reads only for a unit of type 1 (a
//// chest), whose removal then takes its delay from its world object instead of
//// the standard fade. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x355` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0355

/// The body of message 0x0355, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitDestroyed {
  UnitDestroyed(
    unit_id: Int,
    /// Safe by `0x1403d98f0`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    chest_world_object_delay: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitDestroyed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned(
    "chest_world_object_delay",
    message.chest_world_object_delay,
    1,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: UnitDestroyed) -> BitArray {
  bit_stream.must(encode(message), "unit_destroyed")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitDestroyed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(chest_world_object_delay, reader) <- result.try(
    bit_stream.read_unsigned(reader, 1),
  )
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitDestroyed(unit_id:, chest_world_object_delay:))
}
