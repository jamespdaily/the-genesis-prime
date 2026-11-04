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
pub type UnitCreateCreature {
  UnitCreateCreature(
    unit_id: Int,
    creature_id: Int,
    checklist_index: Int,
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
    field_18: Int,
    /// Safe by `opcode.0x262.unit_fields`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_20: Int,
    world_socket_id: Int,
    cluster_id: Int,
    /// Safe by `opcode.0x262.unit_fields`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_24: Int,
    minimap_marker_id: Int,
    display_info_id: Int,
    outfit_info_id: Int,
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
  |> bit_stream.write_unsigned("field_18", message.field_18, 1)
  |> bit_stream.write_constant("second_tag", 1, 2)
  |> bit_stream.write_unsigned("field_20", message.field_20, 64)
  |> bit_stream.write_unsigned("world_socket_id", message.world_socket_id, 14)
  |> bit_stream.write_constant("third_tag", 1, 2)
  |> bit_stream.write_unsigned("cluster_id", message.cluster_id, 32)
  |> bit_stream.write_unsigned("field_24", message.field_24, 18)
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
pub fn decode(body: BitArray) -> Result(UnitCreateCreature, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use reader <- result.try(bit_stream.read_constant(reader, "unit_type", 6, 0))
  use #(creature_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(checklist_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    8,
  ))
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
  use #(field_18, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use reader <- result.try(bit_stream.read_constant(reader, "second_tag", 2, 1))
  use #(field_20, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(world_socket_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use reader <- result.try(bit_stream.read_constant(reader, "third_tag", 2, 1))
  use #(cluster_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_24, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
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
  Ok(UnitCreateCreature(
    unit_id:,
    creature_id:,
    checklist_index:,
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
    field_18:,
    field_20:,
    world_socket_id:,
    cluster_id:,
    field_24:,
    minimap_marker_id:,
    display_info_id:,
    outfit_info_id:,
  ))
}
