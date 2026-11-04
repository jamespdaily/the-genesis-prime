//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_creature), server to client: creates a unit of
//// type 0, a creature, in the world: the Creature2 id, which the client
//// refuses unless it loaded the row, and the quest checklist index, then the
//// values of a player's create: the stats (stat 0 is health, and a creature
//// created with 0 is dead; stat 10 is the level), the movement commands (the
//// server writes kind 2, the position, and kind 14, the rotation), the
//// properties (which may be none, since the client computes each from its
//// tables), both factions, which the client keeps in place of the row's, and
//// the display info, which must be sent since with 0 the creature has no
//// model; the lists the schema does not hold are sent empty. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x262.creature` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/unit_create_tail.{type UnitCreateTail}
import gleam/result

/// The message's number.
pub const message_id = 0x0262

/// The body of message 0x0262, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCreateCreature {
  UnitCreateCreature(
    unit_id: Int,
    creature_id: Int,
    checklist_index: Int,
    tail: UnitCreateTail,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCreateCreature) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_constant("unit_type", 0, 6)
  |> bit_stream.write_unsigned("creature_id", message.creature_id, 18)
  |> bit_stream.write_unsigned("checklist_index", message.checklist_index, 8)
  |> unit_create_tail.write(message.tail)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCreateCreature, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use reader <- result.try(bit_stream.read_constant(reader, "unit_type", 6, 0))
  use #(creature_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(checklist_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    8,
  ))
  use #(tail, reader) <- result.try(unit_create_tail.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCreateCreature(unit_id:, creature_id:, checklist_index:, tail:))
}
