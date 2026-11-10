//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0360 (quest_mention), client to server: the client's notice that
//// a quest is mentioned to the player (bit 1) or that the mention is withdrawn
//// (bit 0), sent only when the wish differs from what it holds; the client has
//// set the quest Mentioned itself in both cases and waits for no answer. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x360` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0360

/// The body of message 0x0360, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestMention {
  QuestMention(quest_id: Int, mentioned: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestMention) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.write_unsigned("mentioned", message.mentioned, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestMention, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(mentioned, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestMention(quest_id:, mentioned:))
}
