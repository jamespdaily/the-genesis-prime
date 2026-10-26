//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07A4 (realm_select_start), client to server: sent when realm
//// select starts; its body is empty. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x7a4` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The body of message 0x07A4, which is empty.
pub type RealmSelectStart {
  RealmSelectStart
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(_message: RealmSelectStart) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RealmSelectStart, DecodeError) {
  bit_stream.new_reader(body)
  |> bit_stream.finish_reading
  |> result.replace(RealmSelectStart)
}
