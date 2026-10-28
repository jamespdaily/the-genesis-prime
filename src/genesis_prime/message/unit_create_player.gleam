//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0262 (unit_create_player), server to client: creates a unit of
//// type 20, a player character, in the world, with its stats, its movement
//// commands (only kind 2, the position) and its properties; the lists the
//// schema does not hold are sent empty. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x262` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/unit_position_command.{type UnitPositionCommand}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat}
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
    group_id: Int,
    owned_unit_ids: List(Int),
    guild_name: String,
    guild_type: Int,
    guild_ids: List(Int),
    bone_values: List(Int),
    pvp_flags: Int,
    premium_tier: Int,
    title_id: Int,
    create_flags: Int,
    stats: List(UnitStat),
    server_time_estimate_start: Int,
    movement_commands: List(UnitPositionCommand),
    properties: List(UnitProperty),
    item_visuals: List(ItemVisual),
    cast_id: Int,
    faction_id: Int,
    base_faction_id: Int,
    tagged_by_unit_id: Int,
    tagged_by_group_id: Int,
    field_31: Int,
    field_33: Int,
    world_socket_id: Int,
    cluster_id: Int,
    field_37: Int,
    minimap_marker_id: Int,
    display_info_id: Int,
    outfit_info_id: Int,
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
  |> bit_stream.write_unsigned("create_flags", message.create_flags, 8)
  |> bit_stream.write_array("stats", message.stats, 5, unit_stat.write)
  |> bit_stream.write_unsigned(
    "server_time_estimate_start",
    message.server_time_estimate_start,
    32,
  )
  |> bit_stream.write_array(
    "movement_commands",
    message.movement_commands,
    5,
    unit_position_command.write,
  )
  |> bit_stream.write_array(
    "properties",
    message.properties,
    8,
    unit_property.write,
  )
  |> bit_stream.write_array(
    "item_visuals",
    message.item_visuals,
    7,
    item_visual.write,
  )
  |> bit_stream.write_constant("no_other_entries", 0, 9)
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned("faction_id", message.faction_id, 14)
  |> bit_stream.write_unsigned("base_faction_id", message.base_faction_id, 14)
  |> bit_stream.write_unsigned(
    "tagged_by_unit_id",
    message.tagged_by_unit_id,
    32,
  )
  |> bit_stream.write_unsigned(
    "tagged_by_group_id",
    message.tagged_by_group_id,
    64,
  )
  |> bit_stream.write_constant("first_tag", 0, 2)
  |> bit_stream.write_unsigned("field_31", message.field_31, 1)
  |> bit_stream.write_constant("second_tag", 1, 2)
  |> bit_stream.write_unsigned("field_33", message.field_33, 64)
  |> bit_stream.write_unsigned("world_socket_id", message.world_socket_id, 14)
  |> bit_stream.write_constant("third_tag", 1, 2)
  |> bit_stream.write_unsigned("cluster_id", message.cluster_id, 32)
  |> bit_stream.write_unsigned("field_37", message.field_37, 18)
  |> bit_stream.write_unsigned(
    "minimap_marker_id",
    message.minimap_marker_id,
    14,
  )
  |> bit_stream.write_unsigned("display_info_id", message.display_info_id, 17)
  |> bit_stream.write_unsigned("outfit_info_id", message.outfit_info_id, 15)
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
  use #(create_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(stats, reader) <- result.try(bit_stream.read_array(
    reader,
    5,
    unit_stat.read,
  ))
  use #(server_time_estimate_start, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(movement_commands, reader) <- result.try(bit_stream.read_array(
    reader,
    5,
    unit_position_command.read,
  ))
  use #(properties, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    unit_property.read,
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
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(faction_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(base_faction_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(tagged_by_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(tagged_by_group_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use reader <- result.try(bit_stream.read_constant(reader, "first_tag", 2, 0))
  use #(field_31, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use reader <- result.try(bit_stream.read_constant(reader, "second_tag", 2, 1))
  use #(field_33, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(world_socket_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use reader <- result.try(bit_stream.read_constant(reader, "third_tag", 2, 1))
  use #(cluster_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_37, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(minimap_marker_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(display_info_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    17,
  ))
  use #(outfit_info_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    15,
  ))
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
    create_flags:,
    stats:,
    server_time_estimate_start:,
    movement_commands:,
    properties:,
    item_visuals:,
    cast_id:,
    faction_id:,
    base_faction_id:,
    tagged_by_unit_id:,
    tagged_by_group_id:,
    field_31:,
    field_33:,
    world_socket_id:,
    cluster_id:,
    field_37:,
    minimap_marker_id:,
    display_info_id:,
    outfit_info_id:,
  ))
}
