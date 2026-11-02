//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00FC (fell_below_floor), client to server: the player has fallen
//// below the world's floor: a bit set when the client found no ground below
//// the player, and the camera's position. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `opcode.0xfc`
//// names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00FC

/// The body of message 0x00FC, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type FellBelowFloor {
  FellBelowFloor(no_ground: Int, camera_x: Int, camera_y: Int, camera_z: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: FellBelowFloor) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("no_ground", message.no_ground, 1)
  |> bit_stream.write_float32_bits("camera_x", message.camera_x)
  |> bit_stream.write_float32_bits("camera_y", message.camera_y)
  |> bit_stream.write_float32_bits("camera_z", message.camera_z)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(FellBelowFloor, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(no_ground, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(camera_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(camera_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(camera_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(FellBelowFloor(no_ground:, camera_x:, camera_y:, camera_z:))
}
