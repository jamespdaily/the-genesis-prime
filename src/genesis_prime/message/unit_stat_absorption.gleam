//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a 0x938 of stat 22: the unit's absorption,
//// what Unit:GetAbsorptionValue returns (the sum of the unit's absorb pools).
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x938` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitStatAbsorption {
  UnitStatAbsorption(value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: UnitStatAbsorption,
) -> Writer {
  writer
  |> bit_stream.write_constant("stat", 22, 5)
  |> bit_stream.write_unsigned("value", record.value, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(UnitStatAbsorption, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "stat", 5, 22))
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(UnitStatAbsorption(value:), reader))
}
