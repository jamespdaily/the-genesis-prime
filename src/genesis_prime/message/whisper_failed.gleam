//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01D9 (whisper_failed), server to client: a whisper could not be
//// delivered: the target's name as sent, the account bit of the whisper and
//// the slot's id; the client prints a whisper error naming the target and
//// frees the slot. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x1d9` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01D9

/// The body of message 0x01D9, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type WhisperFailed {
  WhisperFailed(target_name: List(Int), account: Int, chat_message_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: WhisperFailed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_wide_units("target_name", message.target_name)
  |> bit_stream.write_unsigned("account", message.account, 1)
  |> bit_stream.write_unsigned("chat_message_id", message.chat_message_id, 16)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(WhisperFailed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(target_name, reader) <- result.try(bit_stream.read_wide_units(reader))
  use #(account, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(chat_message_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(WhisperFailed(target_name:, account:, chat_message_id:))
}
