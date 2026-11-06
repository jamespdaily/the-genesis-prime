//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a combat log entry of type 24: the unit
//// that entered or left stealth and whether it is leaving, which the client
//// logs only for a player's unit and for a unit a player owns. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x247.type24` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type CombatLogStealth {
  CombatLogStealth(unit_id: Int, exiting: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: CombatLogStealth) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 24, 6)
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("exiting", record.exiting, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(CombatLogStealth, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 6, 24))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(exiting, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(CombatLogStealth(unit_id:, exiting:), reader))
}
