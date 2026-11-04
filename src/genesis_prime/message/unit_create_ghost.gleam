//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_ghost), server to client: creates a unit of
//// type 23, a ghost: a player's data without its owned units, its PvP flags
//// and its premium tier (the character id, the realm, the name, the race,
//// which the client refuses above 17, the class, the gender, a 64-bit value, a
//// text, a 4-bit value, a list of 64-bit values, a list of 32-bit values and
//// the title), then the values of a player's create; the meanings of the
//// 64-bit value, the text, the 4-bit value and the two lists are not read. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x140096970` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/unit_create_tail.{type UnitCreateTail}
import gleam/result

/// The message's number.
pub const message_id = 0x0262

/// The body of message 0x0262, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCreateGhost {
  UnitCreateGhost(
    unit_id: Int,
    character_id: Int,
    realm_id: Int,
    name: String,
    race_id: Int,
    class_id: Int,
    gender: Int,
    field_9: Int,
    field_10: String,
    field_11: Int,
    field_12: List(Int),
    field_13: List(Int),
    title_id: Int,
    tail: UnitCreateTail,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCreateGhost) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_constant("unit_type", 23, 6)
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.write_unsigned("realm_id", message.realm_id, 14)
  |> bit_stream.write_wide_text("name", message.name)
  |> bit_stream.write_unsigned_below("race_id", message.race_id, 5, 18)
  |> bit_stream.write_unsigned("class_id", message.class_id, 5)
  |> bit_stream.write_unsigned("gender", message.gender, 2)
  |> bit_stream.write_unsigned("field_9", message.field_9, 64)
  |> bit_stream.write_wide_text("field_10", message.field_10)
  |> bit_stream.write_unsigned("field_11", message.field_11, 4)
  |> bit_stream.write_unsigned_array("field_12", message.field_12, 5, 64)
  |> bit_stream.write_unsigned_array("field_13", message.field_13, 6, 32)
  |> bit_stream.write_unsigned("title_id", message.title_id, 14)
  |> unit_create_tail.write(message.tail)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCreateGhost, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use reader <- result.try(bit_stream.read_constant(reader, "unit_type", 6, 23))
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(race_id, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "race_id",
    5,
    18,
  ))
  use #(class_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(gender, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_10, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(field_11, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(field_12, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    5,
    64,
  ))
  use #(field_13, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    6,
    32,
  ))
  use #(title_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(tail, reader) <- result.try(unit_create_tail.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCreateGhost(
    unit_id:,
    character_id:,
    realm_id:,
    name:,
    race_id:,
    class_id:,
    gender:,
    field_9:,
    field_10:,
    field_11:,
    field_12:,
    field_13:,
    title_id:,
    tail:,
  ))
}
