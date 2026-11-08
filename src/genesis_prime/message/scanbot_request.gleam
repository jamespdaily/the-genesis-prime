//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0180 (scanbot_request), client to server: the Scientist path asks
//// for a scanbot: the scanbot profile (a spell id) and whether the request
//// comes from the game command rather than the path's button. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x180` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0180

/// The body of message 0x0180, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ScanbotRequest {
  ScanbotRequest(profile: Int, from_command: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ScanbotRequest) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("profile", message.profile, 32)
  |> bit_stream.write_unsigned("from_command", message.from_command, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ScanbotRequest, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(profile, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(from_command, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ScanbotRequest(profile:, from_command:))
}
