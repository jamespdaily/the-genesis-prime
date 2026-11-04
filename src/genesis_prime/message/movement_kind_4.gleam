//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a movement command of kind 4, a path: the
//// points (three floats each), the speed in units a second as a half float,
//// which the client's apply fails below 0.00001, the path type (0 is straight
//// lines through at least one point, 1 a curve through at least three, and the
//// client's apply fails 2 and 3), a 4-bit mode, a 32-bit value and one bit.
//// Gap: the mode, the 32-bit value and the last bit are not read, and the
//// codec does not check the point count each type needs. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `0x140c1f070` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_float_vector.{type MovementFloatVector}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type MovementKind4 {
  MovementKind4(
    points: List(MovementFloatVector),
    speed: Int,
    path_type: Int,
    mode: Int,
    field_5: Int,
    field_6: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: MovementKind4) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 4, 5)
  |> bit_stream.write_array(
    "points",
    record.points,
    10,
    movement_float_vector.write,
  )
  |> bit_stream.write_half_float_at_least("speed", record.speed, 1.0e-5)
  |> bit_stream.write_unsigned_below("path_type", record.path_type, 2, 2)
  |> bit_stream.write_unsigned("mode", record.mode, 4)
  |> bit_stream.write_unsigned("field_5", record.field_5, 32)
  |> bit_stream.write_unsigned("field_6", record.field_6, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementKind4, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 5, 4))
  use #(points, reader) <- result.try(bit_stream.read_array(
    reader,
    10,
    movement_float_vector.read,
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
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  Ok(#(
    MovementKind4(points:, speed:, path_type:, mode:, field_5:, field_6:),
    reader,
  ))
}
