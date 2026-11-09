//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a place in the held items as message 0x182
//// writes it: the location (9 bits) and the bag index (32 bits). Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x182` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ItemPlace {
  ItemPlace(location: Int, bag_index: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: ItemPlace) -> Writer {
  writer
  |> bit_stream.write_unsigned("location", record.location, 9)
  |> bit_stream.write_unsigned("bag_index", record.bag_index, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(ItemPlace, Reader), DecodeError) {
  use #(location, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  use #(bag_index, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(ItemPlace(location:, bag_index:), reader))
}
