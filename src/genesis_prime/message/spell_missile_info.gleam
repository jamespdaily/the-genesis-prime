//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one missile of a go: the start position, an
//// extra delay in milliseconds, the target unit id, the end position and the
//// force bit. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x7f4` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_position.{type SpellPosition}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellMissileInfo {
  SpellMissileInfo(
    start_position: SpellPosition,
    delay_ms: Int,
    target_unit_id: Int,
    end_position: SpellPosition,
    force_launch: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellMissileInfo) -> Writer {
  writer
  |> spell_position.write(record.start_position)
  |> bit_stream.write_unsigned("delay_ms", record.delay_ms, 32)
  |> bit_stream.write_unsigned("target_unit_id", record.target_unit_id, 32)
  |> spell_position.write(record.end_position)
  |> bit_stream.write_unsigned("force_launch", record.force_launch, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellMissileInfo, Reader), DecodeError) {
  use #(start_position, reader) <- result.try(spell_position.read(reader))
  use #(delay_ms, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(end_position, reader) <- result.try(spell_position.read(reader))
  use #(force_launch, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    SpellMissileInfo(
      start_position:,
      delay_ms:,
      target_unit_id:,
      end_position:,
      force_launch:,
    ),
    reader,
  ))
}
