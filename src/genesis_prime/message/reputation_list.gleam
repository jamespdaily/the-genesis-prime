//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: message 0x25E's reputations: a 14-bit value
//// the handler does not read, then the reputations; a Faction2 id with no row
//// is skipped. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x14008cee0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/reputation.{type Reputation}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ReputationList {
  ReputationList(
    /// Safe by `opcode.0x25e.safe_body`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    field_1: Int,
    reputations: List(Reputation),
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: ReputationList) -> Writer {
  writer
  |> bit_stream.write_unsigned("field_1", record.field_1, 14)
  |> bit_stream.write_array(
    "reputations",
    record.reputations,
    16,
    reputation.write,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(ReputationList, Reader), DecodeError) {
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(reputations, reader) <- result.try(bit_stream.read_array(
    reader,
    16,
    reputation.read,
  ))
  Ok(#(ReputationList(field_1:, reputations:), reader))
}
