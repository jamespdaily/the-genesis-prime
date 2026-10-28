//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one realm of the realm list. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x1400ac130` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type RealmEntry {
  RealmEntry(
    realm_id: Int,
    name: String,
    note_text_id: Int,
    flags: Int,
    pvp_type: Int,
    status: Int,
    population: Int,
    field_8: Int,
    field_9: BitArray,
    field_10: Int,
    count: Int,
    last_played: String,
    field_13: Int,
    field_14: Int,
    field_15: Int,
    field_16: Int,
    field_17: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: RealmEntry) -> Writer {
  writer
  |> bit_stream.write_unsigned("realm_id", record.realm_id, 32)
  |> bit_stream.write_wide_text("name", record.name)
  |> bit_stream.write_unsigned("note_text_id", record.note_text_id, 32)
  |> bit_stream.write_unsigned("flags", record.flags, 32)
  |> bit_stream.write_unsigned("pvp_type", record.pvp_type, 2)
  |> bit_stream.write_unsigned("status", record.status, 3)
  |> bit_stream.write_unsigned("population", record.population, 3)
  |> bit_stream.write_unsigned("field_8", record.field_8, 32)
  |> bit_stream.write_raw_bytes("field_9", record.field_9, 16)
  |> bit_stream.write_unsigned("field_10", record.field_10, 14)
  |> bit_stream.write_unsigned("count", record.count, 32)
  |> bit_stream.write_wide_text("last_played", record.last_played)
  |> bit_stream.write_unsigned("field_13", record.field_13, 64)
  |> bit_stream.write_unsigned("field_14", record.field_14, 16)
  |> bit_stream.write_unsigned("field_15", record.field_15, 16)
  |> bit_stream.write_unsigned("field_16", record.field_16, 16)
  |> bit_stream.write_unsigned("field_17", record.field_17, 16)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(RealmEntry, Reader), DecodeError) {
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(note_text_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(pvp_type, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(status, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(population, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_9, reader) <- result.try(bit_stream.read_raw_bytes(reader, 16))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(last_played, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(field_13, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_15, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_16, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_17, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  Ok(#(
    RealmEntry(
      realm_id:,
      name:,
      note_text_id:,
      flags:,
      pvp_type:,
      status:,
      population:,
      field_8:,
      field_9:,
      field_10:,
      count:,
      last_played:,
      field_13:,
      field_14:,
      field_15:,
      field_16:,
      field_17:,
    ),
    reader,
  ))
}
