//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x092F (player_health), server to client: the player's own health,
//// which the client ignores for any other unit: the unit id, the health and an
//// 18-bit reason mask of which 0x40 is falling and 0x200 breath, which raise a
//// Fall or Suffocate damage floater when health fell; it never marks the
//// player dead. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x92f` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x092F

/// The body of message 0x092F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PlayerHealth {
  PlayerHealth(unit_id: Int, health: Int, reason_mask: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PlayerHealth) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("health", message.health, 32)
  |> bit_stream.write_unsigned("reason_mask", message.reason_mask, 18)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayerHealth, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(health, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(reason_mask, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PlayerHealth(unit_id:, health:, reason_mask:))
}
