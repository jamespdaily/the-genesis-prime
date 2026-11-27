//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0365 (quest_retry), client to server: the client retries a
//// Botched quest, which both accept paths send instead of 0x35b for a quest
//// held Botched: only the quest id; the client changes no state and the
//// server's 0x35c answer sets it. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x365` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0365

/// The body of message 0x0365, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestRetry {
  QuestRetry(quest_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestRetry) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestRetry, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestRetry(quest_id:))
}
