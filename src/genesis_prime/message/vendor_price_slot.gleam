//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one price slot of a vendor item: a 3-bit
//// slot kind (0 uses the item record's own price, which the client computes),
//// the amount and the currency or account currency id. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `0x140097ae0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type VendorPriceSlot {
  VendorPriceSlot(kind: Int, amount: Int, currency_id: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: VendorPriceSlot) -> Writer {
  writer
  |> bit_stream.write_unsigned("kind", record.kind, 3)
  |> bit_stream.write_unsigned("amount", record.amount, 32)
  |> bit_stream.write_unsigned("currency_id", record.currency_id, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(VendorPriceSlot, Reader), DecodeError) {
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(amount, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(currency_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(VendorPriceSlot(kind:, amount:, currency_id:), reader))
}
