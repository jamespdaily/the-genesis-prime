//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01A3 (action_set_amps), server to client: one action set's AMPs:
//// the set's index, which the client refuses above 3 (the whole message), and
//// the EldanAugmentation ids the set holds, which replace the client's list
//// for that set and its unsaved picks. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x1a3` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01A3

/// The body of message 0x01A3, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ActionSetAmps {
  ActionSetAmps(action_set_index: Int, amp_ids: List(Int))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ActionSetAmps) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned_below(
    "action_set_index",
    message.action_set_index,
    3,
    4,
  )
  |> bit_stream.write_unsigned_array("amp_ids", message.amp_ids, 7, 16)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ActionSetAmps, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(action_set_index, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "action_set_index",
    3,
    4,
  ))
  use #(amp_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    7,
    16,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ActionSetAmps(action_set_index:, amp_ids:))
}
