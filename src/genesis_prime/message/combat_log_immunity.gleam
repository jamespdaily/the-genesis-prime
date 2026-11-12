//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a combat log entry of type 18: a hit on a
//// unit immune to its damage, which the client shows as 'for no effect
//// (Immune)' and an Immune floater; only the cast data, the caster, the
//// target, the Spell4 and the combat result. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x247.immunity` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/combat_result.{type CombatResult}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type CombatLogImmunity {
  CombatLogImmunity(
    caster_unit_id: Int,
    target_unit_id: Int,
    spell4_id: Int,
    combat_result: CombatResult,
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: CombatLogImmunity,
) -> Writer {
  writer
  |> bit_stream.write_constant("kind", 18, 6)
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
) -> Result(#(CombatLogImmunity, Reader), DecodeError) {
  use reader <- result.try(bit_stream.read_constant(reader, "kind", 6, 18))
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
    CombatLogImmunity(
      caster_unit_id:,
      target_unit_id:,
      spell4_id:,
      combat_result:,
    ),
    reader,
  ))
}
