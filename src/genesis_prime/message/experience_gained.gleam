//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x01AC (experience_gained), server to client: experience the player
//// gained: the amount added to its experience, the rest experience it used, a
//// third amount the chat shows as its own gain line, the source kind and the
//// unit the experience came from. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x1ac` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x01AC

/// The body of message 0x01AC, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type ExperienceGained {
  ExperienceGained(
    experience: Int,
    rest_experience_used: Int,
    bonus_experience: Int,
    source_kind: Int,
    source_unit_id: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: ExperienceGained) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("experience", message.experience, 32)
  |> bit_stream.write_unsigned(
    "rest_experience_used",
    message.rest_experience_used,
    32,
  )
  |> bit_stream.write_unsigned("bonus_experience", message.bonus_experience, 32)
  |> bit_stream.write_unsigned("source_kind", message.source_kind, 32)
  |> bit_stream.write_unsigned("source_unit_id", message.source_unit_id, 32)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(ExperienceGained, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(experience, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(rest_experience_used, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(bonus_experience, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(source_kind, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(source_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(ExperienceGained(
    experience:,
    rest_experience_used:,
    bonus_experience:,
    source_kind:,
    source_unit_id:,
  ))
}
