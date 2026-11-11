//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x009D (cast_objective_ability), client to server: the client casts
//// the spell of a shortcut the server gave it in message 0x176: its own id for
//// the cast, the Spell4 id the shortcut holds, the target unit id (0 for none)
//// and a position, the target unit's or with none the game's placed position.
//// Its fields are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x9d` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import gleam/result

/// The message's number.
pub const message_id = 0x009D

/// The body of message 0x009D, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type CastObjectiveAbility {
  CastObjectiveAbility(
    client_cast_id: Int,
    spell4_id: Int,
    target_unit_id: Int,
    position_x: Int,
    position_y: Int,
    position_z: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: CastObjectiveAbility) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_cast_id", message.client_cast_id, 32)
  |> bit_stream.write_unsigned("spell4_id", message.spell4_id, 18)
  |> bit_stream.write_unsigned("target_unit_id", message.target_unit_id, 32)
  |> bit_stream.write_float32_bits("position_x", message.position_x)
  |> bit_stream.write_float32_bits("position_y", message.position_y)
  |> bit_stream.write_float32_bits("position_z", message.position_z)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(CastObjectiveAbility, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(position_x, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_y, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(position_z, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(CastObjectiveAbility(
    client_cast_id:,
    spell4_id:,
    target_unit_id:,
    position_x:,
    position_y:,
    position_z:,
  ))
}
