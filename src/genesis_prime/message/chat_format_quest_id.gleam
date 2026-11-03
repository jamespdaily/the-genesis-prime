//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a chat format of type 5, a link to a quest
//// by its id. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x140085ca0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ChatFormatQuestId {
  ChatFormatQuestId(start: Int, end: Int, quest_id: Int)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: ChatFormatQuestId,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 5, 4)
  |> bit_stream.write_unsigned("start", record.start, 16)
  |> bit_stream.write_unsigned("end", record.end, 16)
  |> bit_stream.write_unsigned("quest_id", record.quest_id, 15)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(ChatFormatQuestId, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 4, 5))
  use #(start, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(end, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(quest_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  Ok(#(ChatFormatQuestId(start:, end:, quest_id:), reader))
}
