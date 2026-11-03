//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one movement command the server relays to
//// the players who see a unit: the kinds of the per-frame batch the client's
//// writer builds after the time command (1 platform, 2 position, 8 velocity,
//// 11 move asked, 14 rotation, 24 state flags, 27 mode), every field named,
//// and no kind 0, the sender's own clock. Gap: the other kinds, which game
//// moves queue and the client's writer may send, are not relayed, since
//// opcode.0x637 does not say which queuers exist or what they mean. Its
//// variants are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x637` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_mode.{type MovementMode}
import genesis_prime/message/movement_move_asked.{type MovementMoveAsked}
import genesis_prime/message/movement_platform.{type MovementPlatform}
import genesis_prime/message/movement_rotation.{type MovementRotation}
import genesis_prime/message/movement_state_flags.{type MovementStateFlags}
import genesis_prime/message/movement_velocity.{type MovementVelocity}
import genesis_prime/message/unit_position_command.{type UnitPositionCommand}
import gleam/pair
import gleam/result

/// One item of the union: its first 5 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type RelayedMovement {
  /// Kind 1, read by `movement_platform`. The fact file's `opcode.0x637` names
  /// the kind.
  Platform(MovementPlatform)
  /// Kind 2, read by `unit_position_command`. The fact file's `0x1400ad350`
  /// names the kind.
  Position(UnitPositionCommand)
  /// Kind 8, read by `movement_velocity`. The fact file's
  /// `movement_command.kind_8` names the kind.
  Velocity(MovementVelocity)
  /// Kind 11, read by `movement_move_asked`. The fact file's
  /// `movement_command.kind_11` names the kind.
  MoveAsked(MovementMoveAsked)
  /// Kind 14, read by `movement_rotation`. The fact file's `0x140715350` names
  /// the kind.
  Rotation(MovementRotation)
  /// Kind 24, read by `movement_state_flags`. The fact file's
  /// `movement_command.kind_24` names the kind.
  StateFlags(MovementStateFlags)
  /// Kind 27, read by `movement_mode`. The fact file's
  /// `movement_command.kind_27` names the kind.
  Mode(MovementMode)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: RelayedMovement) -> Writer {
  case record {
    Platform(variant) -> movement_platform.write(writer, variant)
    Position(variant) -> unit_position_command.write(writer, variant)
    Velocity(variant) -> movement_velocity.write(writer, variant)
    MoveAsked(variant) -> movement_move_asked.write(writer, variant)
    Rotation(variant) -> movement_rotation.write(writer, variant)
    StateFlags(variant) -> movement_state_flags.write(writer, variant)
    Mode(variant) -> movement_mode.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(RelayedMovement, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 5))
  case kind {
    1 ->
      reader
      |> movement_platform.read
      |> result.map(pair.map_first(_, Platform))
    2 ->
      reader
      |> unit_position_command.read
      |> result.map(pair.map_first(_, Position))
    8 ->
      reader
      |> movement_velocity.read
      |> result.map(pair.map_first(_, Velocity))
    11 ->
      reader
      |> movement_move_asked.read
      |> result.map(pair.map_first(_, MoveAsked))
    14 ->
      reader
      |> movement_rotation.read
      |> result.map(pair.map_first(_, Rotation))
    24 ->
      reader
      |> movement_state_flags.read
      |> result.map(pair.map_first(_, StateFlags))
    27 -> reader |> movement_mode.read |> result.map(pair.map_first(_, Mode))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "relayed_movement", value: kind))
  }
}
