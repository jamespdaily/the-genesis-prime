//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one stat of a new unit: its id, then its
//// value in the form the stat is read in; stat 0 is the unit's health, and
//// stats 2 to 9 set resource slots 0 to 7 only in the float form. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x140458140` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/unit_stat_value.{type UnitStatValue}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitStat {
  UnitStat(stat_id: Int, value: UnitStatValue)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: UnitStat) -> Writer {
  writer
  |> bit_stream.write_unsigned("stat_id", record.stat_id, 5)
  |> unit_stat_value.write(record.value)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitStat, Reader), DecodeError) {
  use #(stat_id, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(value, reader) <- result.try(unit_stat_value.read(reader))
  Ok(#(UnitStat(stat_id:, value:), reader))
}
