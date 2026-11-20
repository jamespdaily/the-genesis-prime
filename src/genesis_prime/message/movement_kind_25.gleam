//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 25, timed
//// movement state flags: the times (32 bits each, a count in 8 bits), 32 bits
//// of state flags for each time and a 32-bit time offset in ms. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind25 {
  MovementKind25(times: List(Int), state_flags: List(Int), time_offset: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind25) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 25, 5)
  |> bit_stream.write_unsigned_array("times", record.times, 8, 32)
  |> bit_stream.write_unsigned_array_like(
    "state_flags",
    record.state_flags,
    record.times,
    32,
  )
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind25, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 25))
  use #(times, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    8,
    32,
  ))
  use #(state_flags, reader) <- result.try(bit_stream.read_unsigned_array_like(
    reader,
    times,
    32,
  ))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(MovementKind25(times:, state_flags:, time_offset:), reader))
}
