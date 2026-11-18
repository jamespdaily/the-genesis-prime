//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a chat format of type 8, a link that
//// carries a full item record (ReadChatItemRecord 0x140085790): the item's
//// GUID and id, a character id, nine values the client's code names only by
//// width and position, and two counted lists of 32-bit values; the client's
//// own text never makes one (0x140402720). Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140085ca0`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ChatFormatItemRecord {
  ChatFormatItemRecord(
    start: Int,
    end: Int,
    item_guid: Int,
    item_id: Int,
    character_id: Int,
    /// Open: What does the item record's 64-bit value at position 4 mean?
    /// ReadChatItemRecord reads it and its use was not traced;
    /// BuildChatItemLink may read it as the random-stat word
    /// (chat_format_item_record.random_stats).
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_4: Int,
    /// Open: What does the item record's 32-bit value at position 5 mean?
    /// ReadChatItemRecord reads it and its use was not traced;
    /// BuildChatItemLink may read it as the rune slots
    /// (chat_format_item_record.random_stats).
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_5: Int,
    /// Open: What does the item record's 64-bit value at position 6 mean?
    /// ReadChatItemRecord reads it and its use was not traced;
    /// BuildChatItemLink may read it as the 4 + 3x10-bit value
    /// (chat_format_item_record.random_stats).
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_6: Int,
    /// Open: What does the item record's 32-bit value at position 7 mean?
    /// ReadChatItemRecord reads it and no use of it was found.
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_7: Int,
    /// Open: What does the item record's 32-bit value at position 8 mean?
    /// ReadChatItemRecord reads it and its use was not traced;
    /// BuildChatItemLink may read it as the item level
    /// (chat_format_item_record.random_stats).
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_8: Int,
    /// Open: What does the item record's 8-bit value at position 9 mean?
    /// ReadChatItemRecord reads it and no use of it was found.
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_9: Int,
    /// Open: What does the item record's 18-bit value at position 10 mean?
    /// ReadChatItemRecord reads it and its use was not traced;
    /// BuildChatItemLink may read it as the category-143 id
    /// (chat_format_item_record.random_stats).
    /// Safe by `0x140085790`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_10: Int,
    list_a: List(Int),
    list_b: List(Int),
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: ChatFormatItemRecord,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 8, 4)
  |> bit_stream.write_unsigned("start", record.start, 16)
  |> bit_stream.write_unsigned("end", record.end, 16)
  |> bit_stream.write_unsigned("item_guid", record.item_guid, 64)
  |> bit_stream.write_unsigned("item_id", record.item_id, 18)
  |> bit_stream.write_unsigned("character_id", record.character_id, 64)
  |> bit_stream.write_unsigned("field_4", record.field_4, 64)
  |> bit_stream.write_unsigned("field_5", record.field_5, 32)
  |> bit_stream.write_unsigned("field_6", record.field_6, 64)
  |> bit_stream.write_unsigned("field_7", record.field_7, 32)
  |> bit_stream.write_unsigned("field_8", record.field_8, 32)
  |> bit_stream.write_unsigned("field_9", record.field_9, 8)
  |> bit_stream.write_unsigned("field_10", record.field_10, 18)
  |> bit_stream.write_unsigned_array("list_a", record.list_a, 3, 32)
  |> bit_stream.write_unsigned_array("list_b", record.list_b, 4, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(ChatFormatItemRecord, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 4, 8))
  use #(start, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(end, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(item_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(list_a, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    3,
    32,
  ))
  use #(list_b, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    4,
    32,
  ))
  Ok(#(
    ChatFormatItemRecord(
      start:,
      end:,
      item_guid:,
      item_id:,
      character_id:,
      field_4:,
      field_5:,
      field_6:,
      field_7:,
      field_8:,
      field_9:,
      field_10:,
      list_a:,
      list_b:,
    ),
    reader,
  ))
}
