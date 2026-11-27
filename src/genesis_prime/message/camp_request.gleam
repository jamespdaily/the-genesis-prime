//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00BF (camp_request), client to server: the client's request,
//// inside message 0x38C, to start or cancel leaving the world (camping): the
//// bit is 1 to start and 0 to cancel, and does not say whether the camp is a
//// camp or a quit. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xbf` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00BF

/// The body of message 0x00BF, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CampRequest {
  CampRequest(start: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CampRequest) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("start", message.start, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CampRequest, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(start, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CampRequest(start:))
}
