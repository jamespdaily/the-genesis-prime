//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a stat's value in the float form (form 1):
//// the only form a resource stat (2 to 9) is kept in. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140080c60`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitStatFloat {
  UnitStatFloat(value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: UnitStatFloat) -> Writer {
  writer
  |> bit_stream.write_constant("form", 1, 2)
  |> bit_stream.write_float32_bits("value", record.value)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitStatFloat, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "form", 2, 1))
  use #(value, reader) <- result.try(bit_stream.read_float32_bits(reader))
  Ok(#(UnitStatFloat(value:), reader))
}
