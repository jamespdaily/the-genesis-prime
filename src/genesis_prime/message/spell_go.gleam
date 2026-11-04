//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07F4 (spell_go), server to client: a cast goes off: the cast id,
//// the ignore-cooldown bit, the destination, the targets with their effects,
//// the initial and telegraph positions, the missiles and the phase; the client
//// counts the go, keeps the phase, builds a node for each target unit it has,
//// and starts the caster's cooldowns on the first go of a Normal cast unless
//// the bit is set. An effect's result is a bit or a damage description, and a
//// tag of 2 or 3 fails the read. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x7f4` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/spell_initial_position.{type SpellInitialPosition}
import genesis_prime/message/spell_missile_info.{type SpellMissileInfo}
import genesis_prime/message/spell_position.{type SpellPosition}
import genesis_prime/message/spell_target_info.{type SpellTargetInfo}
import genesis_prime/message/spell_telegraph_position.{
  type SpellTelegraphPosition,
}
import gleam/result

/// The message's number.
pub const message_id = 0x07F4

/// The body of message 0x07F4, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellGo {
  SpellGo(
    cast_id: Int,
    ignore_cooldown: Int,
    destination: SpellPosition,
    targets: List(SpellTargetInfo),
    initial_positions: List(SpellInitialPosition),
    telegraph_positions: List(SpellTelegraphPosition),
    missiles: List(SpellMissileInfo),
    phase: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellGo) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("cast_id", message.cast_id, 32)
  |> bit_stream.write_unsigned("ignore_cooldown", message.ignore_cooldown, 1)
  |> spell_position.write(message.destination)
  |> bit_stream.write_array(
    "targets",
    message.targets,
    8,
    spell_target_info.write,
  )
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
  |> bit_stream.write_array(
    "missiles",
    message.missiles,
    8,
    spell_missile_info.write,
  )
  |> bit_stream.write_unsigned("phase", message.phase, 8)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellGo, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(cast_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(ignore_cooldown, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use #(destination, reader) <- result.try(spell_position.read(reader))
  use #(targets, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_target_info.read,
  ))
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
  use #(missiles, reader) <- result.try(bit_stream.read_array(
    reader,
    8,
    spell_missile_info.read,
  ))
  use #(phase, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellGo(
    cast_id:,
    ignore_cooldown:,
    destination:,
    targets:,
    initial_positions:,
    telegraph_positions:,
    missiles:,
    phase:,
  ))
}
