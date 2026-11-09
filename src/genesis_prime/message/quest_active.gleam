//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one active quest of message 0x35F: the
//// Quest2 id, its state (1 or 2: any other crashes the client), the
//// QuestObjective id that fills the quest's placeholder objective (0 for
//// none), the flag word (bit 1 tracked, bit i+2 objective i done), the
//// progress of each objective (no more than the quest has), the quest's time
//// left in milliseconds and each objective's time left (0 changes nothing,
//// which shows a full timer). Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x35f` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type QuestActive {
  QuestActive(
    quest_id: Int,
    state: Int,
    placeholder_objective_id: Int,
    flags: Int,
    progress: List(Int),
    quest_ms_left: Int,
    objective_ms_left: List(Int),
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: QuestActive) -> Writer {
  writer
  |> bit_stream.write_unsigned("quest_id", record.quest_id, 15)
  |> bit_stream.write_unsigned("state", record.state, 4)
  |> bit_stream.write_unsigned(
    "placeholder_objective_id",
    record.placeholder_objective_id,
    32,
  )
  |> bit_stream.write_unsigned("flags", record.flags, 32)
  |> bit_stream.write_unsigned_array("progress", record.progress, 32, 32)
  |> bit_stream.write_unsigned("quest_ms_left", record.quest_ms_left, 32)
  |> bit_stream.write_unsigned_array_like(
    "objective_ms_left",
    record.objective_ms_left,
    record.progress,
    32,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(QuestActive, Reader), DecodeError) {
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(state, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(placeholder_objective_id, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(progress, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    32,
    32,
  ))
  use #(quest_ms_left, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(objective_ms_left, reader) <- result.try(
    bit_stream.read_unsigned_array_like(reader, progress, 32),
  )
  Ok(#(
    QuestActive(
      quest_id:,
      state:,
      placeholder_objective_id:,
      flags:,
      progress:,
      quest_ms_left:,
      objective_ms_left:,
    ),
    reader,
  ))
}
