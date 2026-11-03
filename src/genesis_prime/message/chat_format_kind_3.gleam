//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a chat format of type 3, whose meaning the
//// client's code does not show: its range and one bit. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `0x140085ca0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ChatFormatKind3 {
  ChatFormatKind3(
    start: Int,
    end: Int,
    /// Safe by `0x140085ca0`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_4: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: ChatFormatKind3) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 3, 4)
  |> bit_stream.write_unsigned("start", record.start, 16)
  |> bit_stream.write_unsigned("end", record.end, 16)
  |> bit_stream.write_unsigned("field_4", record.field_4, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(ChatFormatKind3, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 4, 3))
  use #(start, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(end, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(ChatFormatKind3(start:, end:, field_4:), reader))
}
