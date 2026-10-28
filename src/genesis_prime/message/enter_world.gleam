//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00AD (enter_world), server to client: the game server's answer
//// after the player chose a character, with the world the client loads and the
//// position it loads it at. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0xad` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00AD

/// The body of message 0x00AD, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type EnterWorld {
  EnterWorld(
    world_id: Int,
    position_x: Int,
    position_y: Int,
    position_z: Int,
    /// Safe by `opcode.0xad.last_floats`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    field_5: Int,
    /// Safe by `opcode.0xad.last_floats`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    field_6: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: EnterWorld) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("world_id", message.world_id, 15)
  |> bit_stream.write_float32_bits("position_x", message.position_x)
  |> bit_stream.write_float32_bits("position_y", message.position_y)
  |> bit_stream.write_float32_bits("position_z", message.position_z)
  |> bit_stream.write_float32_bits("field_5", message.field_5)
  |> bit_stream.write_float32_bits("field_6", message.field_6)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(EnterWorld, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(world_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(position_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_6, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(EnterWorld(
    world_id:,
    position_x:,
    position_y:,
    position_z:,
    field_5:,
    field_6:,
  ))
}
