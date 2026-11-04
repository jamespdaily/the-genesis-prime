//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 4 as the server
//// writes it, a path: the points (three floats each), the speed in units a
//// second as a half float, which the client's reader fails below 0.00001, the
//// path type (0 is straight lines through at least one point, 1 a curve
//// through at least three, and the reader fails 2 and 3) and a 4-bit mode.
//// Gap: the client's code does not show what the mode, the 32-bit value and
//// the last bit do, so the server writes 0 in the value and the bit, and the
//// codec does not check the point count each type needs. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `movement_command.kind_4` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_path_point.{type MovementPathPoint}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementPath {
  MovementPath(
    points: List(MovementPathPoint),
    speed: Int,
    path_type: Int,
    mode: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementPath) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 4, 5)
  |> bit_stream.write_array(
    "points",
    record.points,
    10,
    movement_path_point.write,
  )
  |> bit_stream.write_half_float_at_least("speed", record.speed, 1.0e-5)
  |> bit_stream.write_unsigned_below("path_type", record.path_type, 2, 2)
  |> bit_stream.write_unsigned("mode", record.mode, 4)
  |> bit_stream.write_constant("value", 0, 32)
  |> bit_stream.write_constant("last_bit", 0, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementPath, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 4))
  use #(points, reader) <- result.try(bit_stream.read_array(
    reader,
    10,
    movement_path_point.read,
  ))
  use #(speed, reader) <- result.try(bit_stream.read_half_float_at_least(
    reader,
    "speed",
    1.0e-5,
  ))
  use #(path_type, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "path_type",
    2,
    2,
  ))
  use #(mode, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use reader <- result.try(bit_stream.read_constant(reader, "value", 32, 0))
  use reader <- result.try(bit_stream.read_constant(reader, "last_bit", 1, 0))
  Ok(#(MovementPath(points:, speed:, path_type:, mode:), reader))
}
