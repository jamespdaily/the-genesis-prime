//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one telegraph position of a cast message:
//// the TelegraphDamage id, a unit id, the target flags, a position, the
//// telegraph's facing and the id of the unit the telegraph is anchored to. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x7ff` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_position.{type SpellPosition}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellTelegraphPosition {
  SpellTelegraphPosition(
    telegraph_damage_id: Int,
    unit_id: Int,
    target_flags: Int,
    position: SpellPosition,
    yaw: Int,
    anchor_unit_id: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: SpellTelegraphPosition,
) -> Writer {
  writer
  |> bit_stream.write_unsigned(
    "telegraph_damage_id",
    record.telegraph_damage_id,
    16,
  )
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("target_flags", record.target_flags, 8)
  |> spell_position.write(record.position)
  |> bit_stream.write_float32_bits("yaw", record.yaw)
  |> bit_stream.write_unsigned("anchor_unit_id", record.anchor_unit_id, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellTelegraphPosition, Reader), DecodeError) {
  use #(telegraph_damage_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(target_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(position, reader) <- result.try(spell_position.read(reader))
  use #(yaw, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(anchor_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  Ok(#(
    SpellTelegraphPosition(
      telegraph_damage_id:,
      unit_id:,
      target_flags:,
      position:,
      yaw:,
      anchor_unit_id:,
    ),
    reader,
  ))
}
