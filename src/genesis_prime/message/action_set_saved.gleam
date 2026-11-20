//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00B2 (action_set_saved), server to client: the answer to the
//// ability builder's Save: the client drops its uncommitted edits and redraws
//// from what its book holds, and with the bit set adds a combat log line for
//// the player; it changes neither the bar nor the tiers. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0xb2` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00B2

/// The body of message 0x00B2, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ActionSetSaved {
  ActionSetSaved(add_combat_log_line: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ActionSetSaved) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "add_combat_log_line",
    message.add_combat_log_line,
    1,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ActionSetSaved, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(add_combat_log_line, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ActionSetSaved(add_combat_log_line:))
}
