//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00E6 (delete_character_result), server to client: the result of a
//// delete-character request; the client removes the character from its list on
//// result 0. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0xe6` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/delete_result.{type DeleteResult}
import gleam/result

/// The message's number.
pub const message_id = 0x00E6

/// The body of message 0x00E6, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type DeleteCharacterResult {
  DeleteCharacterResult(
    result: DeleteResult,
    /// Safe by `opcode.0xe6.value`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    value: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: DeleteCharacterResult) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "result",
    delete_result.to_value(message.result),
    6,
  )
  |> bit_stream.write_unsigned("value", message.value, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(DeleteCharacterResult, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  let result = delete_result.from_value(result)
  use #(value, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(DeleteCharacterResult(result:, value:))
}
