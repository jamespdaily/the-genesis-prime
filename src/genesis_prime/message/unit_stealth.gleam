//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x08F5 (unit_stealth), server to client: a unit enters or leaves
//// stealth: the client sets the unit's stealth state, which Prerequisite type
//// 116 and its own cast checks read; besides the create flag 16 of message
//// 0x262 it is the only message that sets it. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x8f5` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x08F5

/// The body of message 0x08F5, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitStealth {
  UnitStealth(unit_id: Int, stealthed: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitStealth) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("stealthed", message.stealthed, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitStealth, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(stealthed, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitStealth(unit_id:, stealthed:))
}
