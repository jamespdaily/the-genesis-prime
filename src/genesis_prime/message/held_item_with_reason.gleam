//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one held item of message 0x25E, the body of
//// message 0x111: the shared item record and its 6-bit reason. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x14008cee0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/shared_item.{type SharedItem}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type HeldItemWithReason {
  HeldItemWithReason(item: SharedItem, reason: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: HeldItemWithReason,
) -> Writer {
  writer
  |> shared_item.write(record.item)
  |> bit_stream.write_unsigned("reason", record.reason, 6)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(HeldItemWithReason, Reader), DecodeError) {
  use #(item, reader) <- result.try(shared_item.read(reader))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  Ok(#(HeldItemWithReason(item:, reason:), reader))
}
