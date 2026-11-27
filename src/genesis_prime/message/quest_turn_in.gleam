//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x035D (quest_turn_in), client to server: the client turns in a
//// quest: the quest id, the chosen reward's Quest2Reward id (0 when the quest
//// has no choice rows), and whether the communicator opened the dialog; the
//// client sends no state change and waits for the server's 0x35c. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x35d` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x035D

/// The body of message 0x035D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestTurnIn {
  QuestTurnIn(quest_id: Int, reward_id: Int, by_communicator: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestTurnIn) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.write_unsigned("reward_id", message.reward_id, 15)
  |> bit_stream.write_unsigned("by_communicator", message.by_communicator, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestTurnIn, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(reward_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(by_communicator, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestTurnIn(quest_id:, reward_id:, by_communicator:))
}
