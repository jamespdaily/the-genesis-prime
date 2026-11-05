//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_static), server to client: creates a static
//// object in the world: a unit of type 10 (Simple), 11 (Platform) or 32
//// (SimpleCollidable), with a creature's type data, the Creature2 id, which
//// the client takes the object's name, model scale and level from, and the
//// quest checklist index, then the values of a player's create: the stats (a
//// type 32 object created with health 0 is dead; types 10 and 11 never are),
//// the movement commands (kind 2, the position, and kind 14, the rotation),
//// the properties, both factions, the world object the unit claims (0 for
//// none, when the unit builds its own) and the display info, which must be
//// sent since with 0 no model is described. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x262.simple` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/static_unit_type.{type StaticUnitType}
import genesis_prime/message/unit_create_tail.{type UnitCreateTail}
import gleam/result

/// The message's number.
pub const message_id = 0x0262

/// The body of message 0x0262, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCreateStatic {
  UnitCreateStatic(
    unit_id: Int,
    unit_type: StaticUnitType,
    creature_id: Int,
    checklist_index: Int,
    tail: UnitCreateTail,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCreateStatic) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned(
    "unit_type",
    static_unit_type.to_value(message.unit_type),
    6,
  )
  |> bit_stream.write_unsigned("creature_id", message.creature_id, 18)
  |> bit_stream.write_unsigned("checklist_index", message.checklist_index, 8)
  |> unit_create_tail.write(message.tail)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCreateStatic, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(unit_type, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  let unit_type = static_unit_type.from_value(unit_type)
  use #(creature_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(checklist_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    8,
  ))
  use #(tail, reader) <- result.try(unit_create_tail.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCreateStatic(
    unit_id:,
    unit_type:,
    creature_id:,
    checklist_index:,
    tail:,
  ))
}
