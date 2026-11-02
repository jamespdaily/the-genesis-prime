//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00FB (fall_value), client to server: one float the client sends
//// after a flush of its movement, when a movement value of the player's is
//// above 0, likely a fall's distance or speed. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `opcode.0xfb`
//// names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00FB

/// The body of message 0x00FB, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type FallValue {
  FallValue(field_1: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: FallValue) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_float32_bits("field_1", message.field_1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(FallValue, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(FallValue(field_1:))
}
