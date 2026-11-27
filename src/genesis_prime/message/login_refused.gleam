//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x063D (login_refused), server to client: the auth server's refusal
//// of a login, with the reason the client shows; the client reads the float
//// only for reason 21. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x63d` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x063D

/// The body of message 0x063D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type LoginRefused {
  LoginRefused(reason: Int, value: Int, suspension_duration: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: LoginRefused) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("reason", message.reason, 32)
  |> bit_stream.write_unsigned("value", message.value, 32)
  |> bit_stream.write_float32_bits(
    "suspension_duration",
    message.suspension_duration,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: LoginRefused) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(LoginRefused, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(reason, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(suspension_duration, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(LoginRefused(reason:, value:, suspension_duration:))
}
