//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0169 (ability_points), server to client: the player's ability
//// points: the points left to spend and the points the player can hold in all,
//// which the spellbook window shows and the interface menu's Abilities button
//// alerts on while the first is above 0. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x169` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x0169

/// The body of message 0x0169, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type AbilityPoints {
  AbilityPoints(ability_points: Int, total_ability_points: Int)
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: AbilityPoints) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("ability_points", message.ability_points, 32)
  |> bit_stream.write_unsigned(
    "total_ability_points",
    message.total_ability_points,
    32,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: AbilityPoints) -> BitArray {
  bit_stream.must(encode(message), "ability_points")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(AbilityPoints, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(ability_points, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(total_ability_points, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(AbilityPoints(ability_points:, total_ability_points:))
}
