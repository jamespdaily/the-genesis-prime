//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: the part of message 0x262 after the type's
//// data, the same for every unit type: the create flags, the stats, the
//// movement commands, the properties, the item visuals, the cast in progress,
//// the two factions, who tagged the unit, three tagged values and the minimap
//// marker, display info and outfit info; the lists the schema does not hold
//// are sent empty. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x140096fa0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/start_movement.{type StartMovement}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitCreateTail {
  UnitCreateTail(
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
    field_14: Int,
    world_object_id: Int,
    world_socket_id: Int,
    cluster_id: Int,
    /// Safe by `opcode.0x262.unit_fields`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_20: Int,
    minimap_marker_id: Int,
    display_info_id: Int,
    outfit_info_id: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: UnitCreateTail) -> Writer {
  writer
  |> bit_stream.write_unsigned("create_flags", record.create_flags, 8)
  |> bit_stream.write_array("stats", record.stats, 5, unit_stat.write)
  |> bit_stream.write_unsigned(
    "server_time_estimate_start",
    record.server_time_estimate_start,
    32,
  )
  |> bit_stream.write_array(
    "movement_commands",
    record.movement_commands,
    5,
    start_movement.write,
  )
  |> bit_stream.write_array(
    "properties",
    record.properties,
    8,
    unit_property.write,
  )
  |> bit_stream.write_array(
    "item_visuals",
    record.item_visuals,
    7,
    item_visual.write,
  )
  |> bit_stream.write_constant("no_other_entries", 0, 9)
  |> bit_stream.write_unsigned("cast_id", record.cast_id, 32)
  |> bit_stream.write_unsigned("faction_id", record.faction_id, 14)
  |> bit_stream.write_unsigned("base_faction_id", record.base_faction_id, 14)
  |> bit_stream.write_unsigned(
    "tagged_by_unit_id",
    record.tagged_by_unit_id,
    32,
  )
  |> bit_stream.write_unsigned(
    "tagged_by_group_id",
    record.tagged_by_group_id,
    64,
  )
  |> bit_stream.write_constant("first_tag", 0, 2)
  |> bit_stream.write_unsigned("field_14", record.field_14, 1)
  |> bit_stream.write_constant("second_tag", 1, 2)
  |> bit_stream.write_unsigned("world_object_id", record.world_object_id, 64)
  |> bit_stream.write_unsigned("world_socket_id", record.world_socket_id, 14)
  |> bit_stream.write_constant("third_tag", 1, 2)
  |> bit_stream.write_unsigned("cluster_id", record.cluster_id, 32)
  |> bit_stream.write_unsigned("field_20", record.field_20, 18)
  |> bit_stream.write_unsigned(
    "minimap_marker_id",
    record.minimap_marker_id,
    14,
  )
  |> bit_stream.write_unsigned("display_info_id", record.display_info_id, 17)
  |> bit_stream.write_unsigned("outfit_info_id", record.outfit_info_id, 15)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitCreateTail, Reader), DecodeError) {
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
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use reader <- result.try(bit_stream.read_constant(reader, "second_tag", 2, 1))
  use #(world_object_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(world_socket_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use reader <- result.try(bit_stream.read_constant(reader, "third_tag", 2, 1))
  use #(cluster_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_20, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
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
  Ok(#(
    UnitCreateTail(
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
      field_14:,
      world_object_id:,
      world_socket_id:,
      cluster_id:,
      field_20:,
      minimap_marker_id:,
      display_info_id:,
      outfit_info_id:,
    ),
    reader,
  ))
}
