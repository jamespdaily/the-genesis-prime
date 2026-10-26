//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one character of the character list. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x14007f720` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/item_visual.{type ItemVisual}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record and has no use the client's code shows.
pub type CharacterListEntry {
  CharacterListEntry(
    character_id: Int,
    name: String,
    gender: Int,
    race_id: Int,
    class_id: Int,
    faction_id: Int,
    level: Int,
    body_visuals: List(ItemVisual),
    worn_visuals: List(ItemVisual),
    world_id: Int,
    world_zone_id: Int,
    field_12: Int,
    position_x: Int,
    position_y: Int,
    position_z: Int,
    field_16: Int,
    field_17: Int,
    path: Int,
    disabled: Int,
    requires_rename: Int,
    field_21: Int,
    customisation_labels: List(Int),
    customisation_values: List(Int),
    bone_values: List(Int),
    last_logged_out_days: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: CharacterListEntry,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("character_id", record.character_id, 64)
  |> bit_stream.write_wide_text("name", record.name)
  |> bit_stream.write_unsigned("gender", record.gender, 2)
  |> bit_stream.write_unsigned("race_id", record.race_id, 5)
  |> bit_stream.write_unsigned("class_id", record.class_id, 5)
  |> bit_stream.write_unsigned("faction_id", record.faction_id, 32)
  |> bit_stream.write_unsigned("level", record.level, 32)
  |> bit_stream.write_array(
    "body_visuals",
    record.body_visuals,
    32,
    item_visual.write,
  )
  |> bit_stream.write_array(
    "worn_visuals",
    record.worn_visuals,
    32,
    item_visual.write,
  )
  |> bit_stream.write_unsigned("world_id", record.world_id, 15)
  |> bit_stream.write_unsigned("world_zone_id", record.world_zone_id, 15)
  |> bit_stream.write_unsigned("field_12", record.field_12, 14)
  |> bit_stream.write_float32_bits("position_x", record.position_x)
  |> bit_stream.write_float32_bits("position_y", record.position_y)
  |> bit_stream.write_float32_bits("position_z", record.position_z)
  |> bit_stream.write_float32_bits("field_16", record.field_16)
  |> bit_stream.write_float32_bits("field_17", record.field_17)
  |> bit_stream.write_unsigned("path", record.path, 3)
  |> bit_stream.write_unsigned("disabled", record.disabled, 1)
  |> bit_stream.write_unsigned("requires_rename", record.requires_rename, 1)
  |> bit_stream.write_unsigned("field_21", record.field_21, 32)
  |> bit_stream.write_unsigned_array(
    "customisation_labels",
    record.customisation_labels,
    4,
    32,
  )
  |> bit_stream.write_unsigned_array_like(
    "customisation_values",
    record.customisation_values,
    record.customisation_labels,
    32,
  )
  |> bit_stream.write_float32_array("bone_values", record.bone_values, 32)
  |> bit_stream.write_float32_bits(
    "last_logged_out_days",
    record.last_logged_out_days,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(CharacterListEntry, Reader), DecodeError) {
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(gender, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(race_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(class_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(faction_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(level, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(body_visuals, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    item_visual.read,
  ))
  use #(worn_visuals, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    item_visual.read,
  ))
  use #(world_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(world_zone_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    15,
  ))
  use #(field_12, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(position_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_16, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_17, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(path, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(disabled, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(requires_rename, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use #(field_21, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(customisation_labels, reader) <- result.try(
    bit_stream.read_unsigned_array(reader, 4, 32),
  )
  use #(customisation_values, reader) <- result.try(
    bit_stream.read_unsigned_array_like(reader, customisation_labels, 32),
  )
  use #(bone_values, reader) <- result.try(bit_stream.read_float32_array(
    reader,
    32,
  ))
  use #(last_logged_out_days, reader) <- result.try(
    bit_stream.read_float32_bits(reader),
  )
  Ok(#(
    CharacterListEntry(
      character_id:,
      name:,
      gender:,
      race_id:,
      class_id:,
      faction_id:,
      level:,
      body_visuals:,
      worn_visuals:,
      world_id:,
      world_zone_id:,
      field_12:,
      position_x:,
      position_y:,
      position_z:,
      field_16:,
      field_17:,
      path:,
      disabled:,
      requires_rename:,
      field_21:,
      customisation_labels:,
      customisation_values:,
      bone_values:,
      last_logged_out_days:,
    ),
    reader,
  ))
}
