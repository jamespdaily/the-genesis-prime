//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x012B (client_option), client to server: a client option: the
//// option's type (0 the player's input flags, 1 the shared-challenge
//// preference) and its value. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x12b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x012B

/// The body of message 0x012B, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ClientOption {
  ClientOption(option_type: Int, value: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ClientOption) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("option_type", message.option_type, 32)
  |> bit_stream.write_unsigned("value", message.value, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientOption, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(option_type, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ClientOption(option_type:, value:))
}
