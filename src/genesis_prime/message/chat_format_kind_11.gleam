//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a chat format of type 11, whose meaning the
//// client's code does not show: its range and 32 bits. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `0x140085ca0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ChatFormatKind11 {
  ChatFormatKind11(
    start: Int,
    end: Int,
    /// Safe by `0x140085ca0`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_4: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: ChatFormatKind11) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 11, 4)
  |> bit_stream.write_unsigned("start", record.start, 16)
  |> bit_stream.write_unsigned("end", record.end, 16)
  |> bit_stream.write_unsigned("field_4", record.field_4, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(ChatFormatKind11, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 4, 11))
  use #(start, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(end, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(ChatFormatKind11(start:, end:, field_4:), reader))
}
