//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: an effect result of tag 1: a damage
//// description, from which the client makes the floating number, the hit
//// reaction and the combat log line, and which never changes health. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x1400946c0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellEffectDamage {
  SpellEffectDamage(description: SpellDamageDescription)
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: SpellEffectDamage,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 1, 2)
  |> spell_damage_description.write(record.description)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellEffectDamage, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 2, 1))
  use #(description, reader) <- result.try(spell_damage_description.read(reader))
  Ok(#(SpellEffectDamage(description:), reader))
}
