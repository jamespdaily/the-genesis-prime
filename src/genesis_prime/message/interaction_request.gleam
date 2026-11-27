//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07EA (interaction_request), client to server: the client sets the
//// player's interaction: the unit and the interaction kind, where kind 37 is
//// talking to the unit (a quest giver) and unit 0 with kind 0x65 ends the
//// interaction. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x7ea` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x07EA

/// The body of message 0x07EA, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type InteractionRequest {
  InteractionRequest(unit_id: Int, kind: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: InteractionRequest) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("kind", message.kind, 7)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(InteractionRequest, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 7))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(InteractionRequest(unit_id:, kind:))
}
