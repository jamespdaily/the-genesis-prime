//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0881 (unit_tether_anchor), server to client: sets the tether
//// anchor of the unit the receiving client controls: one unit id; the message
//// names no unit, so it never tells a client about another unit's tether. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x881` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0881

/// The body of message 0x0881, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitTetherAnchor {
  UnitTetherAnchor(anchor_unit_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitTetherAnchor) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("anchor_unit_id", message.anchor_unit_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitTetherAnchor, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(anchor_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitTetherAnchor(anchor_unit_id:))
}
