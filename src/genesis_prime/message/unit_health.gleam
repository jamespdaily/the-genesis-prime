//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0937 (unit_health), server to client: a unit's health, which the
//// client stores as sent for any unit but the player's own (it ignores that
//// one); with the dead bit set and health 0 it marks the unit dead. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x937` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0937

/// The body of message 0x0937, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitHealth {
  UnitHealth(unit_id: Int, health: Int, dead: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitHealth) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("health", message.health, 32)
  |> bit_stream.write_unsigned("dead", message.dead, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitHealth, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(health, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(dead, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitHealth(unit_id:, health:, dead:))
}
