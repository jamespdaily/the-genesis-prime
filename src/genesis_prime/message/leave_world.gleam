//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0594 (leave_world), server to client: tells the client to leave
//// the world: with the bit set and a reason of 0 it returns to character
//// select on the same connection, sending 0x7E0; otherwise it shows the error
//// screen with the reason's text. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x594` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0594

/// The body of message 0x0594, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type LeaveWorld {
  LeaveWorld(returning: Int, reason: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: LeaveWorld) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("returning", message.returning, 1)
  |> bit_stream.write_unsigned("reason", message.reason, 5)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(LeaveWorld, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(returning, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(LeaveWorld(returning:, reason:))
}
