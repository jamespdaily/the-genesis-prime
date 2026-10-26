//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0591 (login_accepted), server to client: the auth server's answer
//// that the login is accepted; the client keeps bit 0 of its one value. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x591` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0591

/// The body of message 0x0591, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type LoginAccepted {
  LoginAccepted(field_1: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: LoginAccepted) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("field_1", message.field_1, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(LoginAccepted, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(field_1, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(LoginAccepted(field_1:))
}
