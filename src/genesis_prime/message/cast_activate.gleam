//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0097 (cast_activate), client to server: the client casts the
//// activate spell of a creature it right-clicked, within the creature's
//// activate range: its own id for the cast, then the unit id of the creature,
//// the cast's primary target; the client does not wait for a reply and has set
//// the activate bit on its own cast. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x97` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0097

/// The body of message 0x0097, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CastActivate {
  CastActivate(client_cast_id: Int, target_unit_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CastActivate) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_cast_id", message.client_cast_id, 32)
  |> bit_stream.write_unsigned("target_unit_id", message.target_unit_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CastActivate, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CastActivate(client_cast_id:, target_unit_id:))
}
