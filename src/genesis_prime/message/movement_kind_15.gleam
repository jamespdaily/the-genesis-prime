//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 15, timed
//// rotation keys: the times (32 bits each, a count in 10 bits), a rotation of
//// three 32-bit floats for each time, the path type in 2 bits (0 straight
//// lines, 1 a curve), a 32-bit time offset in ms and the blend bit. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_float_vector.{type MovementFloatVector}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind15 {
  MovementKind15(
    times: List(Int),
    rotations: List(MovementFloatVector),
    path_type: Int,
    time_offset: Int,
    blends: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind15) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 15, 5)
  |> bit_stream.write_unsigned_array("times", record.times, 10, 32)
  |> bit_stream.write_array_like(
    "rotations",
    record.rotations,
    record.times,
    movement_float_vector.write,
  )
  |> bit_stream.write_unsigned("path_type", record.path_type, 2)
  |> bit_stream.write_unsigned("time_offset", record.time_offset, 32)
  |> bit_stream.write_unsigned("blends", record.blends, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind15, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 15))
  use #(times, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    10,
    32,
  ))
  use #(rotations, reader) <- result.try(bit_stream.read_array_like(
    reader,
    times,
    movement_float_vector.read,
  ))
  use #(path_type, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(time_offset, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(blends, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind15(times:, rotations:, path_type:, time_offset:, blends:),
    reader,
  ))
}
