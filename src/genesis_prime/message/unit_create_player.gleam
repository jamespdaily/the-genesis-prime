//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_player), server to client: creates a unit of
//// type 20, a player character, in the world; the lists the client's reader
//// allows are sent empty. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x262` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_visual.{type ItemVisual}
import gleam/result

/// The message's number.
pub const message_id = 0x0262

/// The body of message 0x0262, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type UnitCreatePlayer {
  UnitCreatePlayer(
    unit_id: Int,
    character_id: Int,
    realm_id: Int,
    name: String,
    race_id: Int,
    class_id: Int,
    gender: Int,
    field_9: Int,
    field_10: List(Int),
    field_11: String,
    field_12: Int,
    field_13: List(Int),
    field_14: List(Int),
    path: Int,
    field_16: Int,
    field_17: Int,
    field_18: Int,
    field_20: Int,
    item_visuals: List(ItemVisual),
    field_25: Int,
    faction_id: Int,
    base_faction_id: Int,
    field_28: Int,
    field_29: Int,
    field_31: Int,
    field_33: Int,
    field_34: Int,
    field_36: Int,
    field_37: Int,
    field_38: Int,
    field_39: Int,
    field_40: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitCreatePlayer) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_constant("unit_type", 20, 6)
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.write_unsigned("realm_id", message.realm_id, 14)
  |> bit_stream.write_wide_text("name", message.name)
  |> bit_stream.write_unsigned("race_id", message.race_id, 5)
  |> bit_stream.write_unsigned("class_id", message.class_id, 5)
  |> bit_stream.write_unsigned("gender", message.gender, 2)
  |> bit_stream.write_unsigned("field_9", message.field_9, 64)
  |> bit_stream.write_unsigned_array("field_10", message.field_10, 8, 32)
  |> bit_stream.write_wide_text("field_11", message.field_11)
  |> bit_stream.write_unsigned("field_12", message.field_12, 4)
  |> bit_stream.write_unsigned_array("field_13", message.field_13, 5, 64)
  |> bit_stream.write_unsigned_array("field_14", message.field_14, 6, 32)
  |> bit_stream.write_unsigned("path", message.path, 3)
  |> bit_stream.write_unsigned("field_16", message.field_16, 8)
  |> bit_stream.write_unsigned("field_17", message.field_17, 14)
  |> bit_stream.write_unsigned("field_18", message.field_18, 8)
  |> bit_stream.write_constant("no_tagged_entries", 0, 5)
  |> bit_stream.write_unsigned("field_20", message.field_20, 32)
  |> bit_stream.write_constant("no_kind_entries", 0, 5)
  |> bit_stream.write_constant("no_timed_entries", 0, 8)
  |> bit_stream.write_array(
    "item_visuals",
    message.item_visuals,
    7,
    item_visual.write,
  )
  |> bit_stream.write_constant("no_other_entries", 0, 9)
  |> bit_stream.write_unsigned("field_25", message.field_25, 32)
  |> bit_stream.write_unsigned("faction_id", message.faction_id, 14)
  |> bit_stream.write_unsigned("base_faction_id", message.base_faction_id, 14)
  |> bit_stream.write_unsigned("field_28", message.field_28, 32)
  |> bit_stream.write_unsigned("field_29", message.field_29, 64)
  |> bit_stream.write_constant("first_tag", 0, 2)
  |> bit_stream.write_unsigned("field_31", message.field_31, 1)
  |> bit_stream.write_constant("second_tag", 1, 2)
  |> bit_stream.write_unsigned("field_33", message.field_33, 64)
  |> bit_stream.write_unsigned("field_34", message.field_34, 14)
  |> bit_stream.write_constant("third_tag", 1, 2)
  |> bit_stream.write_unsigned("field_36", message.field_36, 32)
  |> bit_stream.write_unsigned("field_37", message.field_37, 18)
  |> bit_stream.write_unsigned("field_38", message.field_38, 14)
  |> bit_stream.write_unsigned("field_39", message.field_39, 17)
  |> bit_stream.write_unsigned("field_40", message.field_40, 15)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitCreatePlayer, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use reader <- result.try(bit_stream.read_constant(reader, "unit_type", 6, 20))
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(race_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(class_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(gender, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    8,
    32,
  ))
  use #(field_11, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(field_12, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(field_13, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    5,
    64,
  ))
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    6,
    32,
  ))
  use #(path, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(field_16, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(field_17, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(field_18, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "no_tagged_entries",
    5,
    0,
  ))
  use #(field_20, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "no_kind_entries",
    5,
    0,
  ))
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "no_timed_entries",
    8,
    0,
  ))
  use #(item_visuals, reader) <- result.try(bit_stream.read_array(
    reader,
    7,
    item_visual.read,
  ))
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "no_other_entries",
    9,
    0,
  ))
  use #(field_25, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(faction_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(base_faction_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(field_28, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_29, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use reader <- result.try(bit_stream.read_constant(reader, "first_tag", 2, 0))
  use #(field_31, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use reader <- result.try(bit_stream.read_constant(reader, "second_tag", 2, 1))
  use #(field_33, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_34, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use reader <- result.try(bit_stream.read_constant(reader, "third_tag", 2, 1))
  use #(field_36, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_37, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(field_38, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(field_39, reader) <- result.try(bit_stream.read_unsigned(reader, 17))
  use #(field_40, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCreatePlayer(
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
    field_14:,
    path:,
    field_16:,
    field_17:,
    field_18:,
    field_20:,
    item_visuals:,
    field_25:,
    faction_id:,
    base_faction_id:,
    field_28:,
    field_29:,
    field_31:,
    field_33:,
    field_34:,
    field_36:,
    field_37:,
    field_38:,
    field_39:,
    field_40:,
  ))
}
