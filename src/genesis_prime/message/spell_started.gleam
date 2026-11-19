//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07FF (spell_started), server to client: a unit starts a cast: the
//// cast id, the Spell4 id and its root and parent, the caster, the caster's
//// item level, the primary target, the field position and the yaw, the initial
//// and telegraph positions, the own-cast bit and the creature-activate bit;
//// the client shows the caster's cast bar when it has the caster, and starts
//// the player's global cooldown when the caster is the player. Its fields are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x7ff` names the message.

import genesis_prime/gap
import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/spell_initial_position.{type SpellInitialPosition}
import genesis_prime/message/spell_position.{type SpellPosition}
import genesis_prime/message/spell_telegraph_position.{
  type SpellTelegraphPosition,
}
import gleam/result

/// The message's number.
pub const message_id = 0x07FF

/// The body of message 0x07FF, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellStarted {
  SpellStarted(
    cast_id: Int,
    spell4_id: Int,
    root_spell4_id: Int,
    parent_spell4_id: Int,
    caster_unit_id: Int,
    /// Safe by `opcode.0x7ff.caster_item_level`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    caster_item_level: Int,
    primary_target_unit_id: Int,
    position: SpellPosition,
    yaw: Int,
    initial_positions: List(SpellInitialPosition),
    telegraph_positions: List(SpellTelegraphPosition),
    /// Safe by `opcode.0x7ff.own_cast`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    own_cast: Int,
    /// Safe by `opcode.0x7ff.activate`: the client's code gives this field no
    /// use the server needs, and that fact shows its value is safe.
    creature_activate: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellStarted) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned("spell4_id", message.spell4_id, 18)
  |> bit_stream.write_unsigned("root_spell4_id", message.root_spell4_id, 18)
  |> bit_stream.write_unsigned("parent_spell4_id", message.parent_spell4_id, 18)
  |> bit_stream.write_unsigned("caster_unit_id", message.caster_unit_id, 32)
  |> bit_stream.write_unsigned(
    "caster_item_level",
    message.caster_item_level,
    16,
  )
  |> bit_stream.write_unsigned(
    "primary_target_unit_id",
    message.primary_target_unit_id,
    32,
  )
  |> spell_position.write(message.position)
  |> bit_stream.write_float32_bits("yaw", message.yaw)
  |> bit_stream.write_array(
    "initial_positions",
    message.initial_positions,
    8,
    spell_initial_position.write,
  )
  |> bit_stream.write_array(
    "telegraph_positions",
    message.telegraph_positions,
    8,
    spell_telegraph_position.write,
  )
  |> bit_stream.write_unsigned("own_cast", message.own_cast, 1)
  |> bit_stream.write_unsigned(
    "creature_activate",
    message.creature_activate,
    1,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellStarted, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(spell4_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(root_spell4_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(parent_spell4_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(caster_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(caster_item_level, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    16,
  ))
  use #(primary_target_unit_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(position, reader) <- result.try(spell_position.read(reader))
  use #(yaw, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(initial_positions, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_initial_position.read,
  ))
  use #(telegraph_positions, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_telegraph_position.read,
  ))
  use #(own_cast, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(creature_activate, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellStarted(
    cast_id:,
    spell4_id:,
    root_spell4_id:,
    parent_spell4_id:,
    caster_unit_id:,
    caster_item_level:,
    primary_target_unit_id:,
    position:,
    yaw:,
    initial_positions:,
    telegraph_positions:,
    own_cast:,
    creature_activate:,
  ))
}

/// The gaps in this message's codec, which the coverage measure prints.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Cast start",
      missing: "what the client does with the root and parent Spell4 ids of a started cast: no use of them is read",
    ),
  ]
}
