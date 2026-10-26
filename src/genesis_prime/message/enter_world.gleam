//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00AD (enter_world), server to client: the game server's answer
//// after the player chose a character, with which the client enters the world.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0xad` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The body of message 0x00AD, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type EnterWorld {
  EnterWorld(
    field_1: Int,
    field_2: Int,
    field_3: Int,
    field_4: Int,
    field_5: Int,
    field_6: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: EnterWorld) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 15)
  |> bit_stream.write_float32_bits("field_2", message.field_2)
  |> bit_stream.write_float32_bits("field_3", message.field_3)
  |> bit_stream.write_float32_bits("field_4", message.field_4)
  |> bit_stream.write_float32_bits("field_5", message.field_5)
  |> bit_stream.write_float32_bits("field_6", message.field_6)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(EnterWorld, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(field_2, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_3, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_5, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_6, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(EnterWorld(field_1:, field_2:, field_3:, field_4:, field_5:, field_6:))
}
