//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one quest of message 0x35F's second list:
//// the Quest2 id and its state (4 to 7, or 0 to remove the quest). Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x35f` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type QuestKnown {
  QuestKnown(quest_id: Int, state: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: QuestKnown) -> Writer {
  writer
  |> bit_stream.write_unsigned("quest_id", record.quest_id, 15)
  |> bit_stream.write_unsigned("state", record.state, 4)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(QuestKnown, Reader), DecodeError) {
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(state, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  Ok(#(QuestKnown(quest_id:, state:), reader))
}
