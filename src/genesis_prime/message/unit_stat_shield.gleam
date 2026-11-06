//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a 0x938 of stat 20: the unit's shield. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x938` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitStatShield {
  UnitStatShield(value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: UnitStatShield) -> Writer {
  writer
  |> bit_stream.write_constant("stat", 20, 5)
  |> bit_stream.write_unsigned("value", record.value, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitStatShield, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "stat", 5, 20))
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(UnitStatShield(value:), reader))
}
