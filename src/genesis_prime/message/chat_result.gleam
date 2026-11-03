//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01D3 (chat_result), server to client: the server's refusal or
//// report on a line the client sent, on the line's channel, with the result
//// and the slot's id; the client prints the result's text and frees the slot.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x1d3` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/chat_channel_result.{type ChatChannelResult}
import gleam/result

/// The message's number.
pub const message_id = 0x01D3

/// The body of message 0x01D3, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChatResult {
  ChatResult(
    channel_type: Int,
    channel_id: Int,
    result: ChatChannelResult,
    chat_message_id: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChatResult) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("channel_type", message.channel_type, 14)
  |> bit_stream.write_unsigned("channel_id", message.channel_id, 64)
  |> bit_stream.write_unsigned(
    "result",
    chat_channel_result.to_value(message.result),
    5,
  )
  |> bit_stream.write_unsigned("chat_message_id", message.chat_message_id, 16)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChatResult, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(channel_type, reader) <- result.try(bit_stream.read_unsigned(reader, 14))
  use #(channel_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 5))
  let result = chat_channel_result.from_value(result)
  use #(chat_message_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChatResult(channel_type:, channel_id:, result:, chat_message_id:))
}
