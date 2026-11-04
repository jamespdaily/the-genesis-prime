//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one missile of a go: a position, two 32-bit
//// values, a position and one bit; their meanings are not read. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x7f4` names the record.

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
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_1: SpellPosition,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_2: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_3: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_4: SpellPosition,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_5: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellMissileInfo) -> Writer {
  writer
  |> spell_position.write(record.field_1)
  |> bit_stream.write_unsigned("field_2", record.field_2, 32)
  |> bit_stream.write_unsigned("field_3", record.field_3, 32)
  |> spell_position.write(record.field_4)
  |> bit_stream.write_unsigned("field_5", record.field_5, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellMissileInfo, Reader), DecodeError) {
  use #(field_1, reader) <- result.try(spell_position.read(reader))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(spell_position.read(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    SpellMissileInfo(field_1:, field_2:, field_3:, field_4:, field_5:),
    reader,
  ))
}
