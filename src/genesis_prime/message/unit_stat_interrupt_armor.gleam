//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a 0x938 of stat 21: the unit's current
//// Interrupt Armor, which the client clamps to 0 and the unit's maximum. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x938.interrupt_armor` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitStatInterruptArmor {
  UnitStatInterruptArmor(value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: UnitStatInterruptArmor,
) -> Writer {
  writer
  |> bit_stream.write_constant("stat", 21, 5)
  |> bit_stream.write_unsigned("value", record.value, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(UnitStatInterruptArmor, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "stat", 5, 21))
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(UnitStatInterruptArmor(value:), reader))
}
