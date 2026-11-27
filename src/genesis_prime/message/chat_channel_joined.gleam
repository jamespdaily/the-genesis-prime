//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01BC (chat_channel_joined), server to client: joins a chat
//// channel the client does not make itself (a channel type whose ChatChannel
//// row has flag 0x80, such as Zone): the channel's type and id, a name and a
//// slot the client uses only for type 18, and two values the client never
//// reads. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x1bc` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01BC

/// The body of message 0x01BC, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChatChannelJoined {
  ChatChannelJoined(
    channel_type: Int,
    channel_id: Int,
    name: String,
    /// Safe by `opcode.0x1bc`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    unread_4: Int,
    /// Safe by `opcode.0x1bc`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    custom_channel_slot: Int,
    /// Safe by `opcode.0x1bc`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    unread_6: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChatChannelJoined) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("channel_type", message.channel_type, 14)
  |> bit_stream.write_unsigned("channel_id", message.channel_id, 64)
  |> bit_stream.write_wide_text("name", message.name)
  |> bit_stream.write_unsigned("unread_4", message.unread_4, 32)
  |> bit_stream.write_unsigned(
    "custom_channel_slot",
    message.custom_channel_slot,
    32,
  )
  |> bit_stream.write_unsigned("unread_6", message.unread_6, 32)
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: ChatChannelJoined) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChatChannelJoined, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(channel_type, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(channel_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(unread_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(custom_channel_slot, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(unread_6, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChatChannelJoined(
    channel_type:,
    channel_id:,
    name:,
    unread_4:,
    custom_channel_slot:,
    unread_6:,
  ))
}
