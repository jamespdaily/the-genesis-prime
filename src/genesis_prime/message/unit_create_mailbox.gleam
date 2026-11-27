//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_mailbox), server to client: creates a unit of
//// type 12, a mailbox: only the Creature2 id as type data, with no quest
//// checklist index, then the values of a player's create as a static object's
//// (the stats the row records, which the client never creates a mailbox dead
//// for; the movement commands; both factions; the world object the unit
//// claims; the display info). Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `0x140080d30` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/unit_create_tail.{type UnitCreateTail}
import gleam/result

/// The message's number.
pub const message_id = 0x0262

/// The body of message 0x0262, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCreateMailbox {
  UnitCreateMailbox(unit_id: Int, creature_id: Int, tail: UnitCreateTail)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCreateMailbox) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_constant("unit_type", 12, 6)
  |> bit_stream.write_unsigned("creature_id", message.creature_id, 18)
  |> unit_create_tail.write(message.tail)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCreateMailbox, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use reader <- result.try(bit_stream.read_constant(reader, "unit_type", 6, 12))
  use #(creature_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(tail, reader) <- result.try(unit_create_tail.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCreateMailbox(unit_id:, creature_id:, tail:))
}
