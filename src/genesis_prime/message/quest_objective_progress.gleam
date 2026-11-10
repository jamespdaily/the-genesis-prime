//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0361 (quest_objective_progress), server to client: sets the
//// progress of one objective of a quest in the client's log: the client stores
//// it, marks the objective done when it reaches the needed count and raises
//// its objective-updated event; a quest the client does not hold is refused.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x361` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0361

/// The body of message 0x0361, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestObjectiveProgress {
  QuestObjectiveProgress(quest_id: Int, objective_index: Int, progress: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  message: QuestObjectiveProgress,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("quest_id", message.quest_id, 15)
  |> bit_stream.write_unsigned("objective_index", message.objective_index, 32)
  |> bit_stream.write_unsigned("progress", message.progress, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestObjectiveProgress, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(objective_index, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(progress, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestObjectiveProgress(quest_id:, objective_index:, progress:))
}
