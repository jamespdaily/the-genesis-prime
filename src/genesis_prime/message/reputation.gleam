//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one reputation: the Faction2 id and the
//// standing. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x14008cee0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type Reputation {
  Reputation(faction_id: Int, value: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: Reputation) -> Writer {
  writer
  |> bit_stream.write_unsigned("faction_id", record.faction_id, 14)
  |> bit_stream.write_float32_bits("value", record.value)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(Reputation, Reader), DecodeError) {
  use #(faction_id, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(value, reader) <- result.try(bit_stream.read_float32_bits(reader))
  Ok(#(Reputation(faction_id:, value:), reader))
}
