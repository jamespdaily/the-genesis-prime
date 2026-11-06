//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one character entitlement
//// (GetCharacterEntitlement): the entitlement id and the count held. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x14008cee0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type CharacterEntitlement {
  CharacterEntitlement(entitlement_id: Int, count: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: CharacterEntitlement,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("entitlement_id", record.entitlement_id, 14)
  |> bit_stream.write_unsigned("count", record.count, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(CharacterEntitlement, Reader), DecodeError) {
  use #(entitlement_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(CharacterEntitlement(entitlement_id:, count:), reader))
}
