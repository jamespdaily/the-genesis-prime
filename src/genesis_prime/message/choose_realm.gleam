//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07DF (choose_realm), client to server: the client's choice of a
//// realm in realm select; for the current realm it starts character select on
//// the same connection. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x7df` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x07DF

/// The body of message 0x07DF, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChooseRealm {
  ChooseRealm(realm_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChooseRealm) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("realm_id", message.realm_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChooseRealm, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(realm_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChooseRealm(realm_id:))
}
