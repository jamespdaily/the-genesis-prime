//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01C8 (chat_line), server to client: a chat line to show, which
//// the client raises only for a channel it holds with that type and id: the
//// speaker's realm and character id, name and realm name, the text and formats
//// as sent, a bit that colours the name hostile for another faction, and the
//// speaker's unit id, over which a chat bubble shows on a channel whose row
//// has flag 0x10. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x1c8` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/chat_format.{type ChatFormat}
import gleam/result

/// The message's number.
pub const message_id = 0x01C8

/// The body of message 0x01C8, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChatLine {
  ChatLine(
    channel_type: Int,
    channel_id: Int,
    gm: Int,
    from_self: Int,
    auto_response: Int,
    sender_realm_id: Int,
    sender_character_id: Int,
    sender_name: String,
    sender_realm_name: String,
    presence_state: Int,
    text: String,
    formats: List(ChatFormat),
    cross_faction: Int,
    /// Safe by `opcode.0x1c8`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_14: Int,
    unit_id: Int,
    premium_tier: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChatLine) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("channel_type", message.channel_type, 14)
  |> bit_stream.write_unsigned("channel_id", message.channel_id, 64)
  |> bit_stream.write_unsigned("gm", message.gm, 1)
  |> bit_stream.write_unsigned("from_self", message.from_self, 1)
  |> bit_stream.write_unsigned("auto_response", message.auto_response, 1)
  |> bit_stream.write_unsigned("sender_realm_id", message.sender_realm_id, 14)
  |> bit_stream.write_unsigned(
    "sender_character_id",
    message.sender_character_id,
    64,
  )
  |> bit_stream.write_wide_text("sender_name", message.sender_name)
  |> bit_stream.write_wide_text("sender_realm_name", message.sender_realm_name)
  |> bit_stream.write_unsigned("presence_state", message.presence_state, 3)
  |> bit_stream.write_wide_text("text", message.text)
  |> bit_stream.write_array("formats", message.formats, 5, chat_format.write)
  |> bit_stream.write_unsigned("cross_faction", message.cross_faction, 1)
  |> bit_stream.write_unsigned("field_14", message.field_14, 16)
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("premium_tier", message.premium_tier, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChatLine, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(channel_type, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(channel_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(gm, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(from_self, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(auto_response, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(sender_realm_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(sender_character_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(sender_name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(sender_realm_name, reader) <- result.try(bit_stream.read_wide_text(
    reader,
  ))
  use #(presence_state, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    3,
  ))
  use #(text, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(formats, reader) <- result.try(bit_stream.read_array(
    reader,
    5,
    chat_format.read,
  ))
  use #(cross_faction, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned(reader, 16))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(premium_tier, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChatLine(
    channel_type:,
    channel_id:,
    gm:,
    from_self:,
    auto_response:,
    sender_realm_id:,
    sender_character_id:,
    sender_name:,
    sender_realm_name:,
    presence_state:,
    text:,
    formats:,
    cross_faction:,
    field_14:,
    unit_id:,
    premium_tier:,
  ))
}
