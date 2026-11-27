//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07F8 (spell_effect_tick), server to client: results of an effect
//// already sent in a cast, as one tick of a periodic effect: the cast id, the
//// Spell4Effects id, the target unit id and its damage descriptions; the
//// client finds the cast, the target in it and the effect, and applies each
//// description as a 0x7f4 effect info's (floater, hit reaction, combat log).
//// Any of the three not found drops the message without a word, and it never
//// changes health. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x7f8` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription,
}
import gleam/result

/// The message's number.
pub const message_id = 0x07F8

/// The body of message 0x07F8, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellEffectTick {
  SpellEffectTick(
    cast_id: Int,
    spell4_effects_id: Int,
    unit_id: Int,
    descriptions: List(SpellDamageDescription),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellEffectTick) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned(
    "spell4_effects_id",
    message.spell4_effects_id,
    19,
  )
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_array(
    "descriptions",
    message.descriptions,
    8,
    spell_damage_description.write,
  )
  |> bit_stream.finish
}

/// The message as the bytes of its body, for values that fit their fields; a
/// value that does not ends the process, naming the message and the field.
pub fn must_encode(message: SpellEffectTick) -> BitArray {
  bit_stream.must(encode(message), "")
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellEffectTick, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(spell4_effects_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    19,
  ))
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(descriptions, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_damage_description.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellEffectTick(cast_id:, spell4_effects_id:, unit_id:, descriptions:))
}
