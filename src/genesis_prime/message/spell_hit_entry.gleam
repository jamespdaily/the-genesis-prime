//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one hit entry of a damage description:
//// seven 32-bit values and a 3-bit kind, of which 2 and 3 make a multi-hit
//// line and any other a deflect line; the values' meanings are not read. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x1400945e0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellHitEntry {
  SpellHitEntry(
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_1: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_2: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_3: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_4: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_5: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_6: Int,
    /// Safe by `spell.empty_lists`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_7: Int,
    kind: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellHitEntry) -> Writer {
  writer
  |> bit_stream.write_unsigned("field_1", record.field_1, 32)
  |> bit_stream.write_unsigned("field_2", record.field_2, 32)
  |> bit_stream.write_unsigned("field_3", record.field_3, 32)
  |> bit_stream.write_unsigned("field_4", record.field_4, 32)
  |> bit_stream.write_unsigned("field_5", record.field_5, 32)
  |> bit_stream.write_unsigned("field_6", record.field_6, 32)
  |> bit_stream.write_unsigned("field_7", record.field_7, 32)
  |> bit_stream.write_unsigned("kind", record.kind, 3)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SpellHitEntry, Reader), DecodeError) {
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  Ok(#(
    SpellHitEntry(
      field_1:,
      field_2:,
      field_3:,
      field_4:,
      field_5:,
      field_6:,
      field_7:,
      kind:,
    ),
    reader,
  ))
}
