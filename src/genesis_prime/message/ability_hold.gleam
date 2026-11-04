//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x04DB (ability_hold), client to server: the client presses or
//// releases the ability of a bag slot under its hold-to-continue-casting
//// setting, which is on by default: the bag index the ability's item was added
//// at (message 0x111 with location 4), the target unit id (0 for none) and a
//// bit that is 1 when the button goes down and 0 when it comes up; the client
//// makes no cast id of its own for it. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x4db` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x04DB

/// The body of message 0x04DB, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type AbilityHold {
  AbilityHold(bag_index: Int, target_unit_id: Int, held: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: AbilityHold) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("bag_index", message.bag_index, 16)
  |> bit_stream.write_unsigned("target_unit_id", message.target_unit_id, 32)
  |> bit_stream.write_unsigned("held", message.held, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(AbilityHold, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(bag_index, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(held, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(AbilityHold(bag_index:, target_unit_id:, held:))
}
