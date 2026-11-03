//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one entitlement of the account's list: the
//// Entitlement row's id and the count the account holds. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `0x140080710` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type HeldEntitlement {
  HeldEntitlement(entitlement_id: Int, count: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: HeldEntitlement) -> Writer {
  writer
  |> bit_stream.write_unsigned("entitlement_id", record.entitlement_id, 32)
  |> bit_stream.write_unsigned("count", record.count, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(HeldEntitlement, Reader), DecodeError) {
  use #(entitlement_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(HeldEntitlement(entitlement_id:, count:), reader))
}
