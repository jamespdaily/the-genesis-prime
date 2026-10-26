//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x019B (unit_is_player), server to client: tells the client which
//// unit is the player, so the camera and control follow it. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x19b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x019B

/// The body of message 0x019B, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type UnitIsPlayer {
  UnitIsPlayer(unit_id: Int, field_2: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitIsPlayer) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("field_2", message.field_2, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitIsPlayer, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitIsPlayer(unit_id:, field_2:))
}
