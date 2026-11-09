//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x035F (quest_log), server to client: the quest log at login, sent
//// after message 0x25E, which empties the log it fills
//// (opcode.0x35f.entry_order): the completed quests, the quests of the second
//// list (states 4 to 7 and 0), the active quests (states 1 and 2) and the
//// periodic reset time the client seeds its offer picks with; the handler adds
//// to the log and never empties it, and answers an id with no Quest2 row with
//// the Client/Server Data Mismatch disconnect (opcode.0x35f.unknown_quest).
//// Gap: the width of the first list's count and of the quest ids come from the
//// saved C, not an instruction. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x35f` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/quest_active.{type QuestActive}
import genesis_prime/message/quest_completed.{type QuestCompleted}
import genesis_prime/message/quest_known.{type QuestKnown}
import gleam/result

/// The message's number.
pub const message_id = 0x035F

/// The body of message 0x035F, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type QuestLog {
  QuestLog(
    completed: List(QuestCompleted),
    known: List(QuestKnown),
    active: List(QuestActive),
    reset_time: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: QuestLog) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_array(
    "completed",
    message.completed,
    32,
    quest_completed.write,
  )
  |> bit_stream.write_array("known", message.known, 32, quest_known.write)
  |> bit_stream.write_array("active", message.active, 32, quest_active.write)
  |> bit_stream.write_unsigned("reset_time", message.reset_time, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(QuestLog, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(completed, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    quest_completed.read,
  ))
  use #(known, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    quest_known.read,
  ))
  use #(active, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    quest_active.read,
  ))
  use #(reset_time, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(QuestLog(completed:, known:, active:, reset_time:))
}
