//// A record inside a message body: one group of texts of the realm list. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x1400ac590` names the record.
////
//// Generated from `schema.toml` by `gleam run -m genesis_prime/generate_messages`,
//// and never edited by hand.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record and has no use the client's code shows.
pub type TextGroup {
  TextGroup(field_1: Int, texts: List(String))
}

/// Writes the record's fields to the stream.
pub fn write(writer: Writer, record: TextGroup) -> Writer {
  todo
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(TextGroup, Reader), DecodeError) {
  todo
}
