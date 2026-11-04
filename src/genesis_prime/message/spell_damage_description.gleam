//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: a damage description: the raw damage, the
//// scaled raw damage, the damage absorbed, the damage the shield absorbed, the
//// health damage with the overkill, the overkill, the glance amount, the
//// killed bit, the combat result, the damage type and the hit entries. Gap:
//// the second value is a level-scaled raw damage by inference only. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x1400946c0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/combat_result.{type CombatResult}
import genesis_prime/message/damage_type.{type DamageType}
import genesis_prime/message/spell_hit_entry.{type SpellHitEntry}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: Int,
    scaled_raw_damage: Int,
    absorbed: Int,
    shield_absorbed: Int,
    health_damage_with_overkill: Int,
    overkill: Int,
    glance: Int,
    killed: Int,
    combat_result: CombatResult,
    damage_type: DamageType,
    hits: List(SpellHitEntry),
  )
}

/// Writes the record's fields to the stream.
pub fn write(
  writer writer: Writer,
  record record: SpellDamageDescription,
) -> Writer {
  writer
  |> bit_stream.write_unsigned("raw_damage", record.raw_damage, 32)
  |> bit_stream.write_unsigned(
    "scaled_raw_damage",
    record.scaled_raw_damage,
    32,
  )
  |> bit_stream.write_unsigned("absorbed", record.absorbed, 32)
  |> bit_stream.write_unsigned("shield_absorbed", record.shield_absorbed, 32)
  |> bit_stream.write_unsigned(
    "health_damage_with_overkill",
    record.health_damage_with_overkill,
    32,
  )
  |> bit_stream.write_unsigned("overkill", record.overkill, 32)
  |> bit_stream.write_unsigned("glance", record.glance, 32)
  |> bit_stream.write_unsigned("killed", record.killed, 1)
  |> bit_stream.write_unsigned(
    "combat_result",
    combat_result.to_value(record.combat_result),
    4,
  )
  |> bit_stream.write_unsigned(
    "damage_type",
    damage_type.to_value(record.damage_type),
    3,
  )
  |> bit_stream.write_array("hits", record.hits, 8, spell_hit_entry.write)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(SpellDamageDescription, Reader), DecodeError) {
  use #(raw_damage, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(scaled_raw_damage, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(absorbed, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(shield_absorbed, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(health_damage_with_overkill, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(overkill, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(glance, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(killed, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(combat_result, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  let combat_result = combat_result.from_value(combat_result)
  use #(damage_type, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  let damage_type = damage_type.from_value(damage_type)
  use #(hits, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_hit_entry.read,
  ))
  Ok(#(
    SpellDamageDescription(
      raw_damage:,
      scaled_raw_damage:,
      absorbed:,
      shield_absorbed:,
      health_damage_with_overkill:,
      overkill:,
      glance:,
      killed:,
      combat_result:,
      damage_type:,
      hits:,
    ),
    reader,
  ))
}
