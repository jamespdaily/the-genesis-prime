//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x015C (dash), client to server: the player dashes: the direction,
//// 1 Forward, 2 Backward, 3 Left or 4 Right, which the client sends only when
//// its press check of that direction's dash spell passes (100 or more dash
//// energy); the dash is the client's own movement, reported in 0x637, and the
//// client holds no cast of it. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x15c` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x015C

/// The body of message 0x015C, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type Dash {
  Dash(direction: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: Dash) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("direction", message.direction, 3)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(Dash, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(direction, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(Dash(direction:))
}
