//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x025B (create_character), client to server: the request to create
//// a character, which the client sends inside message 0x25C. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x25b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x025B

/// The body of message 0x025B, its fields in wire order. A field named
/// `field_N` is the Nth of the body and has no use the client's code shows.
pub type CreateCharacter {
  CreateCharacter(
    creation_id: Int,
    name: String,
    path: Int,
    customisation_labels: List(Int),
    customisation_values: List(Int),
    bone_values: List(Int),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CreateCharacter) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("creation_id", message.creation_id, 32)
  |> bit_stream.write_wide_text("name", message.name)
  |> bit_stream.write_unsigned("path", message.path, 3)
  |> bit_stream.write_unsigned_array(
    "customisation_labels",
    message.customisation_labels,
    32,
    32,
  )
  |> bit_stream.write_unsigned_array_like(
    "customisation_values",
    message.customisation_values,
    message.customisation_labels,
    32,
  )
  |> bit_stream.write_float32_array("bone_values", message.bone_values, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CreateCharacter, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(creation_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(name, reader) <- result.try(bit_stream.read_wide_text(reader))
  use #(path, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(customisation_labels, reader) <- result.try(
    bit_stream.read_unsigned_array(reader, 32, 32),
  )
  use #(customisation_values, reader) <- result.try(
    bit_stream.read_unsigned_array_like(reader, customisation_labels, 32),
  )
  use #(bone_values, reader) <- result.try(bit_stream.read_float32_array(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CreateCharacter(
    creation_id:,
    name:,
    path:,
    customisation_labels:,
    customisation_values:,
    bone_values:,
  ))
}
