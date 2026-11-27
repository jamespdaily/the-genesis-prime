//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0570 (input_key_set_request), client to server: the client asks
//// for an input key set, the player's key bindings: the key set id, 0 for the
//// account default set. Its fields are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x570` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0570

/// The body of message 0x0570, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type InputKeySetRequest {
  InputKeySetRequest(key_set_id: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: InputKeySetRequest) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("key_set_id", message.key_set_id, 64)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(InputKeySetRequest, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(key_set_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(InputKeySetRequest(key_set_id:))
}
