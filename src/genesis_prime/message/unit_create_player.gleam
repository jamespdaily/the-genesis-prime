//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_player), server to client: creates a unit of
//// type 20, a player character, in the world, with its stats, its movement
//// commands (the server writes kind 2, the position, and kind 14, the
//// rotation) and its properties; the lists the schema does not hold are sent
//// empty. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x262` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/unit_create_tail.{type UnitCreateTail}
import gleam/result

/// The message's number.
pub const message_id = 0x0262

/// The body of message 0x0262, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitCreatePlayer {
  UnitCreatePlayer(
    unit_id: Int,
    character_id: Int,
    realm_id: Int,
    name: String,
    race_id: Int,
    class_id: Int,
    gender: Int,
    group_id: Int,
    owned_unit_ids: List(Int),
    guild_name: String,
    guild_type: Int,
    guild_ids: List(Int),
    bone_values: List(Int),
    pvp_flags: Int,
    premium_tier: Int,
    title_id: Int,
    tail: UnitCreateTail,
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
  |> bit_stream.write_unsigned("group_id", message.group_id, 64)
  |> bit_stream.write_unsigned_array(
    "owned_unit_ids",
    message.owned_unit_ids,
    8,
    32,
  )
  |> bit_stream.write_wide_text("guild_name", message.guild_name)
  |> bit_stream.write_unsigned("guild_type", message.guild_type, 4)
  |> bit_stream.write_unsigned_array("guild_ids", message.guild_ids, 5, 64)
  |> bit_stream.write_unsigned_array("bone_values", message.bone_values, 6, 32)
  |> bit_stream.write_unsigned("pvp_flags", message.pvp_flags, 3)
  |> bit_stream.write_unsigned("premium_tier", message.premium_tier, 8)
  |> bit_stream.write_unsigned("title_id", message.title_id, 14)
  |> unit_create_tail.write(message.tail)
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
  use #(group_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(owned_unit_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    8,
    32,
  ))
  use #(guild_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(guild_type, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(guild_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    5,
    64,
  ))
  use #(bone_values, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    6,
    32,
  ))
  use #(pvp_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(premium_tier, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(title_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(tail, reader) <- result.try(unit_create_tail.read(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitCreatePlayer(
    unit_id:,
    character_id:,
    realm_id:,
    name:,
    race_id:,
    class_id:,
    gender:,
    group_id:,
    owned_unit_ids:,
    guild_name:,
    guild_type:,
    guild_ids:,
    bone_values:,
    pvp_flags:,
    premium_tier:,
    title_id:,
    tail:,
  ))
}
