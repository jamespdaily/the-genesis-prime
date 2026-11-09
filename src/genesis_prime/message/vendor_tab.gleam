//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one tab of a vendor's window: two 32-bit
//// values (the tab's id and its text id, as GetVendorGroups reads them; not
//// read in the client's code). Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x90b` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type VendorTab {
  VendorTab(
    /// Safe by `opcode.0x90b`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_1: Int,
    /// Safe by `opcode.0x90b`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_2: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: VendorTab) -> Writer {
  writer
  |> bit_stream.write_unsigned("field_1", record.field_1, 32)
  |> bit_stream.write_unsigned("field_2", record.field_2, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(VendorTab, Reader), DecodeError) {
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(VendorTab(field_1:, field_2:), reader))
}
