//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01D4 (send_whisper), client to server: the client whispers a line
//// to a character by name (account bit 0) or to an account friend (account bit
//// 1): the target's name and realm name as typed, the line as in 0x1c3, and
//// the slot the client keeps the line in. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x1d4` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/chat_format.{type ChatFormat}
import gleam/result

/// The message's number.
pub const message_id = 0x01D4

/// The body of message 0x01D4, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SendWhisper {
  SendWhisper(
    target_name: List(Int),
    target_realm_name: List(Int),
    text: List(Int),
    formats: List(ChatFormat),
    chat_message_id: Int,
    account: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SendWhisper) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_wide_units("target_name", message.target_name)
  |> bit_stream.write_wide_units("target_realm_name", message.target_realm_name)
  |> bit_stream.write_wide_units("text", message.text)
  |> bit_stream.write_array("formats", message.formats, 5, chat_format.write)
  |> bit_stream.write_unsigned("chat_message_id", message.chat_message_id, 16)
  |> bit_stream.write_unsigned("account", message.account, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SendWhisper, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(target_name, reader) <- result.try(bit_stream.read_wide_units(reader))
  use #(target_realm_name, reader) <- result.try(bit_stream.read_wide_units(
    reader,
  ))
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
  use #(account, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SendWhisper(
    target_name:,
    target_realm_name:,
    text:,
    formats:,
    chat_message_id:,
    account:,
  ))
}
