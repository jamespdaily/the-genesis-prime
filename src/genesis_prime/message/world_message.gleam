//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x038C (world_message), client to server: carries one world message
//// from the client, as a 5-bit value and the world message's whole frame. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x38c` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x038C

/// The body of message 0x038C, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type WorldMessage {
  WorldMessage(field_1: Int, inner_frame: BitArray)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WorldMessage) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 5)
  |> bit_stream.write_whole_frame("inner_frame", message.inner_frame)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WorldMessage, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use #(inner_frame, reader) <- result.try(bit_stream.read_whole_frame(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WorldMessage(field_1:, inner_frame:))
}
