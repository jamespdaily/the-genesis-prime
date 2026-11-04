//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one target of a go: the unit id, an index,
//// the target flags, an instance count, the combat result and the effects on
//// it. Its fields are listed in `schema.toml` with the client's evidence, and
//// the fact file's `opcode.0x7f4` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/combat_result.{type CombatResult}
import genesis_prime/message/spell_effect_info.{type SpellEffectInfo}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellTargetInfo {
  SpellTargetInfo(
    unit_id: Int,
    index: Int,
    flags: Int,
    instance_count: Int,
    combat_result: CombatResult,
    effects: List(SpellEffectInfo),
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellTargetInfo) -> Writer {
  writer
  |> bit_stream.write_unsigned("unit_id", record.unit_id, 32)
  |> bit_stream.write_unsigned("index", record.index, 8)
  |> bit_stream.write_unsigned("flags", record.flags, 8)
  |> bit_stream.write_unsigned("instance_count", record.instance_count, 16)
  |> bit_stream.write_unsigned(
    "combat_result",
    combat_result.to_value(record.combat_result),
    4,
  )
  |> bit_stream.write_array(
    "effects",
    record.effects,
    8,
    spell_effect_info.write,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SpellTargetInfo, Reader), DecodeError) {
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(index, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(flags, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(instance_count, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use #(combat_result, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  let combat_result = combat_result.from_value(combat_result)
  use #(effects, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_effect_info.read,
  ))
  Ok(#(
    SpellTargetInfo(
      unit_id:,
      index:,
      flags:,
      instance_count:,
      combat_result:,
      effects:,
    ),
    reader,
  ))
}
