//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0002 (close_notice), client to server: the network layer's notice
//// that the client is closing a connection, which travels bare with an empty
//// body and gets no answer. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x2` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0002

/// The body of message 0x0002, which is empty.
pub type CloseNotice {
  CloseNotice
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: CloseNotice) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CloseNotice, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(CloseNotice)
}
