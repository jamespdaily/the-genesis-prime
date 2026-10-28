//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one group of texts of the realm list. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x1400ac590` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type TextGroup {
  TextGroup(field_1: Int, texts: List(String))
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: TextGroup) -> Writer {
  writer
  |> bit_stream.write_unsigned("field_1", record.field_1, 32)
  |> bit_stream.write_wide_texts("texts", record.texts, 8)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(TextGroup, Reader), DecodeError) {
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(texts, reader) <- result.try(bit_stream.read_wide_texts(reader, 8))
  Ok(#(TextGroup(field_1:, texts:), reader))
}
