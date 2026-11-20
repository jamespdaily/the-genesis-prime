//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one live cast of message 0x262: the caster,
//// the primary target, the cast id, the Spell4 id, whether the cast is started
//// (bit 1) or gone (bit 0), the targets with their effects as a go lists them,
//// the initial positions and the telegraph positions. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140094bf0`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_initial_position.{type SpellInitialPosition}
import genesis_prime/message/spell_target_info.{type SpellTargetInfo}
import genesis_prime/message/spell_telegraph_position.{
  type SpellTelegraphPosition,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitCreateCast {
  UnitCreateCast(
    caster_unit_id: Int,
    primary_target_unit_id: Int,
    cast_id: Int,
    spell4_id: Int,
    started: Int,
    targets: List(SpellTargetInfo),
    initial_positions: List(SpellInitialPosition),
    telegraph_positions: List(SpellTelegraphPosition),
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: UnitCreateCast) -> Writer {
  writer
  |> bit_stream.write_unsigned("caster_unit_id", record.caster_unit_id, 32)
  |> bit_stream.write_unsigned(
    "primary_target_unit_id",
    record.primary_target_unit_id,
    32,
  )
  |> bit_stream.write_unsigned("cast_id", record.cast_id, 32)
  |> bit_stream.write_unsigned("spell4_id", record.spell4_id, 18)
  |> bit_stream.write_unsigned("started", record.started, 1)
  |> bit_stream.write_array(
    "targets",
    record.targets,
    32,
    spell_target_info.write,
  )
  |> bit_stream.write_array(
    "initial_positions",
    record.initial_positions,
    8,
    spell_initial_position.write,
  )
  |> bit_stream.write_array(
    "telegraph_positions",
    record.telegraph_positions,
    8,
    spell_telegraph_position.write,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitCreateCast, Reader), DecodeError) {
  use #(caster_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(primary_target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(started, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(targets, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    spell_target_info.read,
  ))
  use #(initial_positions, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_initial_position.read,
  ))
  use #(telegraph_positions, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_telegraph_position.read,
  ))
  Ok(#(
    UnitCreateCast(
      caster_unit_id:,
      primary_target_unit_id:,
      cast_id:,
      spell4_id:,
      started:,
      targets:,
      initial_positions:,
      telegraph_positions:,
    ),
    reader,
  ))
}
