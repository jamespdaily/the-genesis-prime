//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x014B (rename_character_result), server to client: the result of a
//// rename request; on result 18 the client gives the listed character the
//// name. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x14b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/rename_result.{type RenameResult}
import gleam/result

/// The message's number.
pub const message_id = 0x014B

/// The body of message 0x014B, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type RenameCharacterResult {
  RenameCharacterResult(result: RenameResult, character_id: Int, name: String)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: RenameCharacterResult) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned(
    "result",
    rename_result.to_value(message.result),
    6,
  )
  |> bit_stream.write_unsigned("character_id", message.character_id, 64)
  |> bit_stream.write_wide_text("name", message.name)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(RenameCharacterResult, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(result, reader) <- result.try(bit_stream.read_unsigned(reader, 6))
  let result = rename_result.from_value(result)
  use #(character_id, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(RenameCharacterResult(result:, character_id:, name:))
}
