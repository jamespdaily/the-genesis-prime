//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x019D (action_set), server to client: one action set of the action
//// bar: the set's index, which the client refuses above 3 (the whole message),
//// a 2-bit value it keeps per set, the result (1 is ok, any other raises
//// ActionSetError) and the shortcuts, each replacing the bar slot it names,
//// which the client refuses above 47. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x19d` names the
//// message.

import genesis_prime/message/action_shortcut.{type ActionShortcut}
import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x019D

/// The body of message 0x019D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ActionSet {
  ActionSet(
    action_set_index: Int,
    field_2: Int,
    result: Int,
    shortcuts: List(ActionShortcut),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ActionSet) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned_below(
    "action_set_index",
    message.action_set_index,
    3,
    4,
  )
  |> bit_stream.write_unsigned("field_2", message.field_2, 2)
  |> bit_stream.write_unsigned("result", message.result, 6)
  |> bit_stream.write_array(
    "shortcuts",
    message.shortcuts,
    6,
    action_shortcut.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ActionSet, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(action_set_index, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "action_set_index",
    3,
    4,
  ))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 2))
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use #(shortcuts, reader) <- result.try(bit_stream.read_array(
    reader,
    6,
    action_shortcut.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ActionSet(action_set_index:, field_2:, result:, shortcuts:))
}
