//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x00DC (create_character_result), server to client: the result of a
//// create-character request, with the new character's id. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0xdc` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/create_result.{type CreateResult}
import gleam/result

/// The message's number.
pub const message_id = 0x00DC

/// The body of message 0x00DC, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type CreateCharacterResult {
  CreateCharacterResult(character_id: Int, field_2: Int, result: CreateResult)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CreateCharacterResult) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.write_unsigned("field_2", message.field_2, 32)
  |> bit_stream.write_unsigned(
    "result",
    create_result.to_value(message.result),
    6,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CreateCharacterResult, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  let result = create_result.from_value(result)
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CreateCharacterResult(character_id:, field_2:, result:))
}
