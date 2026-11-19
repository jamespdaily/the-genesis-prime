//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 3 as the server
//// writes it, a timed path: the times of its points (32 bits each, a count in
//// 10 bits) and the points (three floats each, one for each time), which the
//// client draws as straight lines between the points, holding the first before
//// the first time and the last after the last. The path type is 0 (straight
//// lines; 1 is a curve), and the server writes 0 in the value that shifts the
//// sampling time and 0 in the blend bit. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `movement_command.kind_3` names the record.

import genesis_prime/gap
import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_float_vector.{type MovementFloatVector}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementTimedPath {
  MovementTimedPath(times: List(Int), points: List(MovementFloatVector))
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: MovementTimedPath,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 3, 5)
  |> bit_stream.write_unsigned_array("times", record.times, 10, 32)
  |> bit_stream.write_array_like(
    "points",
    record.points,
    record.times,
    movement_float_vector.write,
  )
  |> bit_stream.write_constant("path_type", 0, 2)
  |> bit_stream.write_constant("value", 0, 32)
  |> bit_stream.write_constant("blend", 0, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(MovementTimedPath, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 3))
  use #(times, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    10,
    32,
  ))
  use #(points, reader) <- result.try(bit_stream.read_array_like(
    reader,
    times,
    movement_float_vector.read,
  ))
  use reader <- result.try(bit_stream.read_constant(reader, "path_type", 2, 0))
  use reader <- result.try(bit_stream.read_constant(reader, "value", 32, 0))
  use reader <- result.try(bit_stream.read_constant(reader, "blend", 1, 0))
  Ok(#(MovementTimedPath(times:, points:), reader))
}

/// The gaps in this record's codec, which the coverage measure prints.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Movement paths",
      missing: "that the times of a timed path rise and that it holds a point: the codec writes and reads any times and any number of points",
    ),
  ]
}
