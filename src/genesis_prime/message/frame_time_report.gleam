//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0240 (frame_time_report), client to server: the client's report
//// to the world server of its frame timing (telemetry): two 32-bit values,
//// four floats and a 32-bit value; nothing the player sees depends on it. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x240.body` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0240

/// The body of message 0x0240, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type FrameTimeReport {
  FrameTimeReport(
    window_mean_frame: Int,
    window_slowest_frame: Int,
    camera_x: Int,
    camera_y: Int,
    camera_z: Int,
    /// Open: What does slot 1 of the game's camera object (game 0x71a8, else
    /// 0x71a0) return at the window's slowest frame? The recorded values fit a
    /// heading in radians; it is not a time step (opcode.0x240.camera_value).
    field_6: Int,
    session_mean_frame: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: FrameTimeReport) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "window_mean_frame",
    message.window_mean_frame,
    32,
  )
  |> bit_stream.write_unsigned(
    "window_slowest_frame",
    message.window_slowest_frame,
    32,
  )
  |> bit_stream.write_float32_bits("camera_x", message.camera_x)
  |> bit_stream.write_float32_bits("camera_y", message.camera_y)
  |> bit_stream.write_float32_bits("camera_z", message.camera_z)
  |> bit_stream.write_float32_bits("field_6", message.field_6)
  |> bit_stream.write_unsigned(
    "session_mean_frame",
    message.session_mean_frame,
    32,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: FrameTimeReport) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(FrameTimeReport, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(window_mean_frame, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(window_slowest_frame, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(camera_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(camera_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(camera_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_6, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(session_mean_frame, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(FrameTimeReport(
    window_mean_frame:,
    window_slowest_frame:,
    camera_x:,
    camera_y:,
    camera_z:,
    field_6:,
    session_mean_frame:,
  ))
}
