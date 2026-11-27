//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0176 (quest_spell_shortcut), server to client: the server adds or
//// removes a spell shortcut tied to a path, quest or objective: the spell, the
//// kind (0 path, 1 quest, 2 objective), the id of that path, quest or
//// objective, and a bit that is 1 to add and 0 to remove. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x176` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0176

/// The body of message 0x0176, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestSpellShortcut {
  QuestSpellShortcut(spell4_id: Int, kind: Int, id: Int, add: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestSpellShortcut) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("spell4_id", message.spell4_id, 18)
  |> bit_stream.write_unsigned("kind", message.kind, 3)
  |> bit_stream.write_unsigned("id", message.id, 32)
  |> bit_stream.write_unsigned("add", message.add, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestSpellShortcut, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(add, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestSpellShortcut(spell4_id:, kind:, id:, add:))
}
