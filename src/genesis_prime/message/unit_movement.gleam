//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0638 (unit_movement), server to client: movement commands for a
//// unit the server moves: the unit, the server's time, a bit that resets the
//// unit's movement, a bit the unit keeps, and at most 31 commands in the
//// layout of 0x637's. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x638` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/movement_command.{type MovementCommand}
import gleam/result

/// The message's number.
pub const message_id = 0x0638

/// The body of message 0x0638, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type UnitMovement {
  UnitMovement(
    unit_id: Int,
    server_time: Int,
    reset_movement: Int,
    kept: Int,
    commands: List(MovementCommand),
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: UnitMovement) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_unsigned("server_time", message.server_time, 32)
  |> bit_stream.write_unsigned("reset_movement", message.reset_movement, 1)
  |> bit_stream.write_unsigned("kept", message.kept, 1)
  |> bit_stream.write_array(
    "commands",
    message.commands,
    5,
    movement_command.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(UnitMovement, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(server_time, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(reset_movement, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    1,
  ))
  use #(kept, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(commands, reader) <- result.try(bit_stream.read_array(
    reader,
    5,
    movement_command.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(UnitMovement(unit_id:, server_time:, reset_movement:, kept:, commands:))
}
