//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a combat log entry of type 19: a spell of
//// one unit interrupted a cast of another, shown as '<target> is interrupted
//// while casting <spell> by <caster>'s <interrupting spell>'; the interrupting
//// spell's Spell4 id, the cast result, then the cast data: the unit whose
//// spell did the interrupting, the unit interrupted, the interrupted spell's
//// Spell4 id and the combat result. Its fields are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x247.interrupted`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/cast_result.{type CastResult}
import genesis_prime/message/combat_result.{type CombatResult}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type CombatLogInterrupted {
  CombatLogInterrupted(
    interrupting_spell4_id: Int,
    cast_result: CastResult,
    caster_unit_id: Int,
    target_unit_id: Int,
    spell4_id: Int,
    combat_result: CombatResult,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: CombatLogInterrupted,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 19, 6)
  |> bit_stream.write_unsigned(
    "interrupting_spell4_id",
    record.interrupting_spell4_id,
    18,
  )
  |> bit_stream.write_unsigned(
    "cast_result",
    cast_result.to_value(record.cast_result),
    9,
  )
  |> bit_stream.write_unsigned("caster_unit_id", record.caster_unit_id, 32)
  |> bit_stream.write_unsigned("target_unit_id", record.target_unit_id, 32)
  |> bit_stream.write_unsigned("spell4_id", record.spell4_id, 18)
  |> bit_stream.write_unsigned(
    "combat_result",
    combat_result.to_value(record.combat_result),
    4,
  )
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(CombatLogInterrupted, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 6, 19))
  use #(interrupting_spell4_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(cast_result, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  let cast_result = cast_result.from_value(cast_result)
  use #(caster_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(combat_result, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  let combat_result = combat_result.from_value(combat_result)
  Ok(#(
    CombatLogInterrupted(
      interrupting_spell4_id:,
      cast_result:,
      caster_unit_id:,
      target_unit_id:,
      spell4_id:,
      combat_result:,
    ),
    reader,
  ))
}
