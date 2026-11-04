//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one initial position of a cast message: a
//// unit id, 8 bits, a position, a float and 32 bits; their meanings are not
//// read. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x7ff` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_position.{type SpellPosition}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellInitialPosition {
  SpellInitialPosition(
    unit_id: Int,
    field_2: Int,
    position: SpellPosition,
    field_4: Int,
    field_5: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: SpellInitialPosition,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("field_2", record.field_2, 8)
  |> spell_position.write(record.position)
  |> bit_stream.write_float32_bits("field_4", record.field_4)
  |> bit_stream.write_unsigned("field_5", record.field_5, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellInitialPosition, Reader), DecodeError) {
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(position, reader) <- result.try(spell_position.read(reader))
  use #(field_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(
    SpellInitialPosition(unit_id:, field_2:, position:, field_4:, field_5:),
    reader,
  ))
}
