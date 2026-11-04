//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: the result of an effect: the tag in 2 bits
//// picks the layout, and the client's reader fails a tag of 2 or 3. Its
//// variants are listed in `schema.toml` with the client's evidence, and the
//// fact file's `0x140094890` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_effect_bit.{type SpellEffectBit}
import genesis_prime/message/spell_effect_damage.{type SpellEffectDamage}
import gleam/pair
import gleam/result

/// One item of the union: its first 2 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type SpellEffectResult {
  /// Kind 0, read by `spell_effect_bit`. The fact file's `0x140094890` names
  /// the kind.
  Bit(SpellEffectBit)
  /// Kind 1, read by `spell_effect_damage`. The fact file's `0x140094890` names
  /// the kind.
  Damage(SpellEffectDamage)
}

/// Writes the variant's record to the stream.
pub fn write(
  writer writer: Writer,
  record record: SpellEffectResult,
) -> Writer {
  case record {
    Bit(variant) -> spell_effect_bit.write(writer, variant)
    Damage(variant) -> spell_effect_damage.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellEffectResult, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 2))
  case kind {
    0 -> reader |> spell_effect_bit.read |> result.map(pair.map_first(_, Bit))
    1 ->
      reader
      |> spell_effect_damage.read
      |> result.map(pair.map_first(_, Damage))
    _ ->
      Error(bit_stream.UnexpectedValue(
        field: "spell_effect_result",
        value: kind,
      ))
  }
}
