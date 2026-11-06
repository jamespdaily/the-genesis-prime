//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one property of a unit in a 0x262 or a
//// 0x93a: its id (a UnitProperty2 id), its base and its value; the value is
//// the one Unit:GetMaxHealth reads for id 7. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x1404584b0`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type UnitProperty {
  UnitProperty(property_id: Int, base: Int, value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: UnitProperty) -> Writer {
  writer
  |> bit_stream.write_unsigned("property_id", record.property_id, 8)
  |> bit_stream.write_float32_bits("base", record.base)
  |> bit_stream.write_float32_bits("value", record.value)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitProperty, Reader), DecodeError) {
  use #(property_id, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(base, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(value, reader) <- result.try(bit_stream.read_float32_bits(reader))
  Ok(#(UnitProperty(property_id:, base:, value:), reader))
}
