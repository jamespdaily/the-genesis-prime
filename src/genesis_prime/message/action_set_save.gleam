//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00B1 (action_set_save), client to server: the ability builder's
//// Save: the twelve Spell4Base ids of the active action set's slots (eight
//// abilities, the gadget, the path ability and two zeros; 0 is an empty slot),
//// the active set, the tier edits and the AMP ids, which the client sends
//// without checking that a slot is unlocked, an ability is held or an id
//// appears once. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xb1` names the message.

import genesis_prime/message/action_set_tier_change.{type ActionSetTierChange}
import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00B1

/// The body of message 0x00B1, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ActionSetSave {
  ActionSetSave(
    spell4_base_ids: List(Int),
    action_set_index: Int,
    tier_changes: List(ActionSetTierChange),
    amp_ids: List(Int),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ActionSetSave) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned_array(
    "spell4_base_ids",
    message.spell4_base_ids,
    4,
    32,
  )
  |> bit_stream.write_unsigned("action_set_index", message.action_set_index, 3)
  |> bit_stream.write_array(
    "tier_changes",
    message.tier_changes,
    5,
    action_set_tier_change.write,
  )
  |> bit_stream.write_unsigned_array("amp_ids", message.amp_ids, 7, 16)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: ActionSetSave) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ActionSetSave, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(spell4_base_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    4,
    32,
  ))
  use #(action_set_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    3,
  ))
  use #(tier_changes, reader) <- result.try(bit_stream.read_array(
    reader,
    5,
    action_set_tier_change.read,
  ))
  use #(amp_ids, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    7,
    16,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ActionSetSave(spell4_base_ids:, action_set_index:, tier_changes:, amp_ids:))
}
