//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one format of a chat line: the type in 4
//// bits picks the layout of its data, and the client's reader refuses a type
//// of 12 to 15. Gap: type 8, a full item record, has no variant, since its
//// layout is not described (0x140085790), so a line holding one is read as a
//// failure. Its variants are listed in `schema.toml` with the client's
//// evidence, and the fact file's `0x140085ca0` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/chat_format_article_id.{type ChatFormatArticleId}
import genesis_prime/message/chat_format_filter_mask.{type ChatFormatFilterMask}
import genesis_prime/message/chat_format_item_guid.{type ChatFormatItemGuid}
import genesis_prime/message/chat_format_item_id.{type ChatFormatItemId}
import genesis_prime/message/chat_format_kind_0.{type ChatFormatKind0}
import genesis_prime/message/chat_format_kind_1.{type ChatFormatKind1}
import genesis_prime/message/chat_format_kind_11.{type ChatFormatKind11}
import genesis_prime/message/chat_format_kind_2.{type ChatFormatKind2}
import genesis_prime/message/chat_format_kind_3.{type ChatFormatKind3}
import genesis_prime/message/chat_format_navigation_point.{
  type ChatFormatNavigationPoint,
}
import genesis_prime/message/chat_format_quest_id.{type ChatFormatQuestId}
import gleam/pair
import gleam/result

/// One item of the union: its first 4 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type ChatFormat {
  /// Kind 0, read by `chat_format_kind_0`.
  Kind0(ChatFormatKind0)
  /// Kind 1, read by `chat_format_kind_1`.
  Kind1(ChatFormatKind1)
  /// Kind 2, read by `chat_format_kind_2`.
  Kind2(ChatFormatKind2)
  /// Kind 3, read by `chat_format_kind_3`.
  Kind3(ChatFormatKind3)
  /// Kind 4, read by `chat_format_item_id`. The fact file's `0x140085ca0` names
  /// the kind.
  ItemId(ChatFormatItemId)
  /// Kind 5, read by `chat_format_quest_id`. The fact file's `0x140085ca0`
  /// names the kind.
  QuestId(ChatFormatQuestId)
  /// Kind 6, read by `chat_format_article_id`. The fact file's `0x140085ca0`
  /// names the kind.
  ArticleId(ChatFormatArticleId)
  /// Kind 7, read by `chat_format_filter_mask`. The fact file's `0x140085ca0`
  /// names the kind.
  FilterMask(ChatFormatFilterMask)
  /// Kind 9, read by `chat_format_item_guid`. The fact file's `0x140085ca0`
  /// names the kind.
  ItemGuid(ChatFormatItemGuid)
  /// Kind 10, read by `chat_format_navigation_point`. The fact file's
  /// `0x140085ca0` names the kind.
  NavigationPoint(ChatFormatNavigationPoint)
  /// Kind 11, read by `chat_format_kind_11`.
  Kind11(ChatFormatKind11)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: ChatFormat) -> Writer {
  case record {
    Kind0(variant) -> chat_format_kind_0.write(writer, variant)
    Kind1(variant) -> chat_format_kind_1.write(writer, variant)
    Kind2(variant) -> chat_format_kind_2.write(writer, variant)
    Kind3(variant) -> chat_format_kind_3.write(writer, variant)
    ItemId(variant) -> chat_format_item_id.write(writer, variant)
    QuestId(variant) -> chat_format_quest_id.write(writer, variant)
    ArticleId(variant) -> chat_format_article_id.write(writer, variant)
    FilterMask(variant) -> chat_format_filter_mask.write(writer, variant)
    ItemGuid(variant) -> chat_format_item_guid.write(writer, variant)
    NavigationPoint(variant) ->
      chat_format_navigation_point.write(writer, variant)
    Kind11(variant) -> chat_format_kind_11.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(ChatFormat, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 4))
  case kind {
    0 ->
      reader
      |> chat_format_kind_0.read
      |> result.map(pair.map_first(_, Kind0))
    1 ->
      reader
      |> chat_format_kind_1.read
      |> result.map(pair.map_first(_, Kind1))
    2 ->
      reader
      |> chat_format_kind_2.read
      |> result.map(pair.map_first(_, Kind2))
    3 ->
      reader
      |> chat_format_kind_3.read
      |> result.map(pair.map_first(_, Kind3))
    4 ->
      reader
      |> chat_format_item_id.read
      |> result.map(pair.map_first(_, ItemId))
    5 ->
      reader
      |> chat_format_quest_id.read
      |> result.map(pair.map_first(_, QuestId))
    6 ->
      reader
      |> chat_format_article_id.read
      |> result.map(pair.map_first(_, ArticleId))
    7 ->
      reader
      |> chat_format_filter_mask.read
      |> result.map(pair.map_first(_, FilterMask))
    9 ->
      reader
      |> chat_format_item_guid.read
      |> result.map(pair.map_first(_, ItemGuid))
    10 ->
      reader
      |> chat_format_navigation_point.read
      |> result.map(pair.map_first(_, NavigationPoint))
    11 ->
      reader
      |> chat_format_kind_11.read
      |> result.map(pair.map_first(_, Kind11))
    _ -> Error(bit_stream.UnexpectedValue(field: "chat_format", value: kind))
  }
}
