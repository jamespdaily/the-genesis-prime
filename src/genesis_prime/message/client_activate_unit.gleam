//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00B3 (client_activate_unit), client to server: the client uses a
//// unit whose creature has no activate spell, at once and with no cast: the
//// unit id alone; a unit with an activate spell is cast at with message 0x97
//// instead. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0xb3` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00B3

/// The body of message 0x00B3, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ClientActivateUnit {
  ClientActivateUnit(unit_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ClientActivateUnit) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ClientActivateUnit, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ClientActivateUnit(unit_id:))
}
