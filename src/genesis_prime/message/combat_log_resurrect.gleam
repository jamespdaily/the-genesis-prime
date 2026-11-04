//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a combat log entry of type 23: the unit
//// that came back, which the client logs only for a player or a ghost or a
//// unit one owns. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x247.death` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type CombatLogResurrect {
  CombatLogResurrect(unit_id: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: CombatLogResurrect,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 23, 6)
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(CombatLogResurrect, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 6, 23))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(CombatLogResurrect(unit_id:), reader))
}
