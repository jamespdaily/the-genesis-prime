//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0106 (generic_error), server to client: a generic error: the code
//// of GameLib.CodeEnumGenericError, whose text the client looks up and raises
//// as an event (a Vendor code shows in the open vendor window only). Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0x106` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0106

/// The body of message 0x0106, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type GenericError {
  GenericError(code: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: GenericError) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("code", message.code, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(GenericError, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(code, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(GenericError(code:))
}
