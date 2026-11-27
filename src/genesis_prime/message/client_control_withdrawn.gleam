//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0639 (client_control_withdrawn), server to client: takes back the
//// client's control of the controlled unit's movement, so the client stops
//// sending message 0x637 until message 0x636 gives it back; its body is empty.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x639` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0639

/// The body of message 0x0639, which is empty.
pub type ClientControlWithdrawn {
  ClientControlWithdrawn
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(
  _message: ClientControlWithdrawn,
) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientControlWithdrawn, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(ClientControlWithdrawn)
}
