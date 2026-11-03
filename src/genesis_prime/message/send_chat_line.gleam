//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01C3 (send_chat_line), client to server: the client says a line
//// on a chat channel it holds (Say, Yell, Emote, Zone and the others except a
//// slash command and the two whispers): the channel's type and id, the text,
//// its formats and the slot the client keeps the line in until the server
//// answers. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x1c3` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/chat_format.{type ChatFormat}
import gleam/result

/// The message's number.
pub const message_id = 0x01C3

/// The body of message 0x01C3, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SendChatLine {
  SendChatLine(
    channel_type: Int,
    channel_id: Int,
    text: List(Int),
    formats: List(ChatFormat),
    chat_message_id: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SendChatLine) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("channel_type", message.channel_type, 14)
  |> bit_stream.write_unsigned("channel_id", message.channel_id, 64)
  |> bit_stream.write_wide_units("text", message.text)
  |> bit_stream.write_array("formats", message.formats, 5, chat_format.write)
  |> bit_stream.write_unsigned("chat_message_id", message.chat_message_id, 16)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SendChatLine, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(channel_type, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(channel_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(text, reader) <- result.try(bit_stream.read_wide_units(reader))
  use #(formats, reader) <- result.try(bit_stream.read_array(
    reader,
    5,
    chat_format.read,
  ))
  use #(chat_message_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SendChatLine(channel_type:, channel_id:, text:, formats:, chat_message_id:))
}
