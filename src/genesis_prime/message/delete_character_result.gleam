//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00E6 (delete_character_result), server to client: the result of a
//// delete-character request; the client removes the character from its list on
//// result 0. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xe6` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x00E6

/// The body of message 0x00E6, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type DeleteCharacterResult {
  DeleteCharacterResult(result: Int, field_2: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: DeleteCharacterResult) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("result", message.result, 6)
  |> bit_stream.write_unsigned("field_2", message.field_2, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(DeleteCharacterResult, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(DeleteCharacterResult(result:, field_2:))
}
