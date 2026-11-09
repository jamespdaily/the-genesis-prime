//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a reward property's value in the integer
//// form (type 1), the only form the server writes: the client also reads types
//// 0 and 2 as a 32-bit float, which are a gap until a property the server
//// sends needs one, and type 3 refuses the message. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140c1f178`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type RewardPropertyInteger {
  RewardPropertyInteger(value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: RewardPropertyInteger,
) -> Writer {
  writer
  |> bit_stream.write_constant("type", 1, 2)
  |> bit_stream.write_unsigned("value", record.value, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(RewardPropertyInteger, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "type", 2, 1))
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(RewardPropertyInteger(value:), reader))
}
