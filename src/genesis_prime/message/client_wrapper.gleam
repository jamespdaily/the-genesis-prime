//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0244 (client_wrapper), client to server: the wrapper every
//// message the client sends travels in, holding one whole inner frame. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x244` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0244

/// The body of message 0x0244, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type ClientWrapper {
  ClientWrapper(inner_frame: BitArray)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ClientWrapper) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_whole_frame("inner_frame", message.inner_frame)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientWrapper, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(inner_frame, reader) <- result.try(bit_stream.read_whole_frame(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ClientWrapper(inner_frame:))
}
