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
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/start_movement.{type StartMovement}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat}
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
    create_flags: Int,
    stats: List(UnitStat),
    server_time_estimate_start: Int,
    movement_commands: List(StartMovement),
    properties: List(UnitProperty),
    item_visuals: List(ItemVisual),
    cast_id: Int,
    faction_id: Int,
    base_faction_id: Int,
    tagged_by_unit_id: Int,
    tagged_by_group_id: Int,
    /// Safe by `opcode.0x262.unit_fields`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_28: Int,
    /// Safe by `opcode.0x262.unit_fields`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_30: Int,
    world_socket_id: Int,
    cluster_id: Int,
    /// Safe by `opcode.0x262.unit_fields`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_34: Int,
    minimap_marker_id: Int,
    display_info_id: Int,
    outfit_info_id: Int,
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
    start_movement.write,
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
  |> bit_stream.write_unsigned("field_28", message.field_28, 1)
  |> bit_stream.write_constant("second_tag", 1, 2)
  |> bit_stream.write_unsigned("field_30", message.field_30, 64)
  |> bit_stream.write_unsigned("world_socket_id", message.world_socket_id, 14)
  |> bit_stream.write_constant("third_tag", 1, 2)
  |> bit_stream.write_unsigned("cluster_id", message.cluster_id, 32)
  |> bit_stream.write_unsigned("field_34", message.field_34, 18)
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
    start_movement.read,
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
  use #(field_28, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use reader <- result.try(bit_stream.read_constant(reader, "second_tag", 2, 1))
  use #(field_30, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(world_socket_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use reader <- result.try(bit_stream.read_constant(reader, "third_tag", 2, 1))
  use #(cluster_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_34, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
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
    field_28:,
    field_30:,
    world_socket_id:,
    cluster_id:,
    field_34:,
    minimap_marker_id:,
    display_info_id:,
    outfit_info_id:,
  ))
}
