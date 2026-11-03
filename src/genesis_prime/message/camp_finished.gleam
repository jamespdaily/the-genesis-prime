//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00C0 (camp_finished), client to server: the client's notice,
//// inside message 0x38C, that its camp has finished and it leaves the world
//// now; its body is empty, and a quit sends it before the countdown ends. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `opcode.0xc0` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00C0

/// The body of message 0x00C0, which is empty.
pub type CampFinished {
  CampFinished
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: CampFinished) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CampFinished, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(CampFinished)
}
