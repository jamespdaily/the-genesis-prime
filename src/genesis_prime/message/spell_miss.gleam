//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one missed target of a cast: the unit id,
//// the reason (0 is Dodge, which the client shows as Deflect) and a time in
//// milliseconds the client adds to the miss's visual. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x7fb` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/miss_reason.{type MissReason}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellMiss {
  SpellMiss(
    unit_id: Int,
    reason: MissReason,
    /// Safe by `opcode.0x7fb.time`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    time_ms: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellMiss) -> Writer {
  writer
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("reason", miss_reason.to_value(record.reason), 4)
  |> bit_stream.write_unsigned("time_ms", record.time_ms, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SpellMiss, Reader), DecodeError) {
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  let reason = miss_reason.from_value(reason)
  use #(time_ms, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(SpellMiss(unit_id:, reason:, time_ms:), reader))
}
