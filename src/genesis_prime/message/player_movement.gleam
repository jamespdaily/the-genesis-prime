//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x0637 (player_movement), client to server: the player's movement
//// commands: the client's clock in milliseconds, then the commands that
//// changed since the last message. Its fields are listed in `schema.toml` with
//// the client's evidence, and the fact file's `opcode.0x637` names the
//// message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/movement_command.{type MovementCommand}
import gleam/result

/// The message's number.
pub const message_id = 0x0637

/// The body of message 0x0637, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type PlayerMovement {
  PlayerMovement(client_clock: Int, commands: List(MovementCommand))
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: PlayerMovement) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("client_clock", message.client_clock, 32)
  |> bit_stream.write_array(
    "commands",
    message.commands,
    32,
    movement_command.write,
  )
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(PlayerMovement, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(client_clock, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(commands, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    movement_command.read,
  ))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(PlayerMovement(client_clock:, commands:))
}
