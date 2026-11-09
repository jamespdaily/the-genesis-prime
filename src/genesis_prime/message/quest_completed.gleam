//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one completed quest of message 0x35F: the
//// Quest2 id and whether it was completed in its current period (a quest with
//// a period and the bit clear goes straight into the completed set, so its
//// group may offer it again). Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x35f` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type QuestCompleted {
  QuestCompleted(quest_id: Int, in_current_period: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: QuestCompleted) -> Writer {
  writer
  |> bit_stream.write_unsigned("quest_id", record.quest_id, 15)
  |> bit_stream.write_unsigned("in_current_period", record.in_current_period, 1)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(QuestCompleted, Reader), DecodeError) {
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(in_current_period, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  Ok(#(QuestCompleted(quest_id:, in_current_period:), reader))
}
