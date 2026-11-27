//// Stub of message 0x015C: the schema and the generated codec come in the next commit.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}

/// The message's number.
pub const message_id = 0x015C

pub type Dash {
  Dash(direction: Int)
}

pub fn encode(_message: Dash) -> Result(BitArray, EncodeError) {
  Ok(<<>>)
}

pub fn decode(_body: BitArray) -> Result(Dash, DecodeError) {
  Ok(Dash(direction: 0))
}
