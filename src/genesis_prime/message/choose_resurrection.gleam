//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x015A (choose_resurrection), client to server: the player chose
//// how to come back: the player's unit id (not the ghost's), the choice and a
//// 32-bit value the client's Death addon always sends as 0; the client does
//// not check that the choice was offered and waits for no answer. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x15a` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x015A

/// The body of message 0x015A, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ChooseResurrection {
  ChooseResurrection(unit_id: Int, choice: Int, field_3: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ChooseResurrection) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("choice", message.choice, 7)
  |> bit_stream.write_unsigned("field_3", message.field_3, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ChooseResurrection, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(choice, reader) <- result.try(bit_stream.read_unsigned(reader, 7))
  use #(field_3, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ChooseResurrection(unit_id:, choice:, field_3:))
}
