//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x035C (quest_state), server to client: sets a quest's state (1
//// Accepted, 2 Achieved, 3 Completed, 4 Botched, 5 Mentioned, 6 Abandoned, 7
//// Ignored) and, when its objective id is not 0 and the quest has a
//// placeholder objective, replaces that placeholder with the QuestObjective; a
//// quest the client does not know is refused. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x35c` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x035C

/// The body of message 0x035C, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestState {
  QuestState(quest_id: Int, state: Int, objective_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestState) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.write_unsigned("state", message.state, 32)
  |> bit_stream.write_unsigned("objective_id", message.objective_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestState, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(state, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(objective_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestState(quest_id:, state:, objective_id:))
}
