//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x07FD (spell_cast_confirmed), server to client: accepts the
//// player's pending cast and gives it its id: the client's id, the server's,
//// the primary target, the field position and the yaw, then the initial and
//// telegraph positions; the client files the pending cast under the server's
//// id and starts it. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x7fd` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/spell_initial_position.{type SpellInitialPosition}
import genesis_prime/message/spell_position.{type SpellPosition}
import genesis_prime/message/spell_telegraph_position.{
  type SpellTelegraphPosition,
}
import gleam/result

/// The message's number.
pub const message_id = 0x07FD

/// The body of message 0x07FD, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type SpellCastConfirmed {
  SpellCastConfirmed(
    client_cast_id: Int,
    server_cast_id: Int,
    primary_target_unit_id: Int,
    position: SpellPosition,
    yaw: Int,
    initial_positions: List(SpellInitialPosition),
    telegraph_positions: List(SpellTelegraphPosition),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: SpellCastConfirmed) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_cast_id", message.client_cast_id, 32)
  |> bit_stream.write_unsigned("server_cast_id", message.server_cast_id, 32)
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
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(SpellCastConfirmed, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(server_cast_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
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
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(SpellCastConfirmed(
    client_cast_id:,
    server_cast_id:,
    primary_target_unit_id:,
    position:,
    yaw:,
    initial_positions:,
    telegraph_positions:,
  ))
}
