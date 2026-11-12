//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one effect on a target of a go: the
//// Spell4Effects id, the effect instance id, the delay in milliseconds, the
//// effect's lifetime in milliseconds (0 never ends by time) and the result,
//// which is a bit or a damage description. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x140094890`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/spell_effect_result.{type SpellEffectResult}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellEffectInfo {
  SpellEffectInfo(
    spell4_effects_id: Int,
    instance_id: Int,
    delay_ms: Int,
    /// Safe by `opcode.0x7f4.effect_time`: the client's code gives this field
    /// no use the server needs, and that fact shows its value is safe.
    field_4: Int,
    result: SpellEffectResult,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SpellEffectInfo) -> Writer {
  writer
  |> bit_stream.write_unsigned(
    "spell4_effects_id",
    record.spell4_effects_id,
    19,
  )
  |> bit_stream.write_unsigned("instance_id", record.instance_id, 32)
  |> bit_stream.write_unsigned("delay_ms", record.delay_ms, 32)
  |> bit_stream.write_unsigned("field_4", record.field_4, 32)
  |> spell_effect_result.write(record.result)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SpellEffectInfo, Reader), DecodeError) {
  use #(spell4_effects_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    19,
  ))
  use #(instance_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(delay_ms, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(result, reader) <- result.try(spell_effect_result.read(reader))
  Ok(#(
    SpellEffectInfo(
      spell4_effects_id:,
      instance_id:,
      delay_ms:,
      field_4:,
      result:,
    ),
    reader,
  ))
}
