//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one movement command of a message about a
//// unit's movement: the kinds of the per-frame batch the client's writer
//// builds after the time command (1 platform, 2 position, 8 velocity, 11 move
//// asked, 14 rotation, 24 state flags, 27 mode), which the server relays to
//// the players who see a unit, every field named, and the nine a server that
//// moves a unit writes itself, 0 (the time its later commands apply at), 3 (a
//// timed path), 4 (a path), 10, 13, 21 and 26 (the velocity, move, rotation
//// and state that follow a path by default), 18 (face a unit) and 19 (face a
//// point). Gap: the other kinds, which game moves queue and the client's
//// writer may send, are not relayed, since opcode.0x637 does not say which
//// queuers exist or what they mean. Its variants are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x637` names the
//// union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_face_point.{type MovementFacePoint}
import genesis_prime/message/movement_face_unit.{type MovementFaceUnit}
import genesis_prime/message/movement_kind_10.{type MovementKind10}
import genesis_prime/message/movement_kind_13.{type MovementKind13}
import genesis_prime/message/movement_kind_21.{type MovementKind21}
import genesis_prime/message/movement_kind_26.{type MovementKind26}
import genesis_prime/message/movement_mode.{type MovementMode}
import genesis_prime/message/movement_move_asked.{type MovementMoveAsked}
import genesis_prime/message/movement_path.{type MovementPath}
import genesis_prime/message/movement_platform.{type MovementPlatform}
import genesis_prime/message/movement_rotation.{type MovementRotation}
import genesis_prime/message/movement_state_flags.{type MovementStateFlags}
import genesis_prime/message/movement_time.{type MovementTime}
import genesis_prime/message/movement_timed_path.{type MovementTimedPath}
import genesis_prime/message/movement_velocity.{type MovementVelocity}
import genesis_prime/message/unit_position_command.{type UnitPositionCommand}
import gleam/pair
import gleam/result

/// One item of the union: its first 5 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type RelayedMovement {
  /// Kind 0, read by `movement_time`. The fact file's `movement_command.kind_0`
  /// names the kind.
  Time(MovementTime)
  /// Kind 1, read by `movement_platform`. The fact file's `opcode.0x637` names
  /// the kind.
  Platform(MovementPlatform)
  /// Kind 2, read by `unit_position_command`. The fact file's `0x1400ad350`
  /// names the kind.
  Position(UnitPositionCommand)
  /// Kind 3, read by `movement_timed_path`. The fact file's
  /// `movement_command.kind_3` names the kind.
  TimedPath(MovementTimedPath)
  /// Kind 4, read by `movement_path`. The fact file's `movement_command.kind_4`
  /// names the kind.
  Path(MovementPath)
  /// Kind 8, read by `movement_velocity`. The fact file's
  /// `movement_command.kind_8` names the kind.
  Velocity(MovementVelocity)
  /// Kind 10, read by `movement_kind_10`. The fact file's
  /// `movement_command.defaults_with_kind_4_path` names the kind.
  VelocityDefault(MovementKind10)
  /// Kind 11, read by `movement_move_asked`. The fact file's
  /// `movement_command.kind_11` names the kind.
  MoveAsked(MovementMoveAsked)
  /// Kind 13, read by `movement_kind_13`. The fact file's
  /// `movement_command.kind_13` names the kind.
  MoveDefault(MovementKind13)
  /// Kind 14, read by `movement_rotation`. The fact file's `0x140715350` names
  /// the kind.
  Rotation(MovementRotation)
  /// Kind 18, read by `movement_face_unit`. The fact file's
  /// `movement_command.kind_18` names the kind.
  FaceUnit(MovementFaceUnit)
  /// Kind 19, read by `movement_face_point`. The fact file's
  /// `movement_command.kind_19` names the kind.
  FacePoint(MovementFacePoint)
  /// Kind 21, read by `movement_kind_21`. The fact file's
  /// `movement_command.kind_21` names the kind.
  RotationDefault(MovementKind21)
  /// Kind 24, read by `movement_state_flags`. The fact file's
  /// `movement_command.kind_24` names the kind.
  StateFlags(MovementStateFlags)
  /// Kind 26, read by `movement_kind_26`. The fact file's
  /// `movement_command.defaults_with_kind_4_path` names the kind.
  StateDefault(MovementKind26)
  /// Kind 27, read by `movement_mode`. The fact file's
  /// `movement_command.kind_27` names the kind.
  Mode(MovementMode)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: RelayedMovement) -> Writer {
  case record {
    Time(variant) -> movement_time.write(writer, variant)
    Platform(variant) -> movement_platform.write(writer, variant)
    Position(variant) -> unit_position_command.write(writer, variant)
    TimedPath(variant) -> movement_timed_path.write(writer, variant)
    Path(variant) -> movement_path.write(writer, variant)
    Velocity(variant) -> movement_velocity.write(writer, variant)
    VelocityDefault(variant) -> movement_kind_10.write(writer, variant)
    MoveAsked(variant) -> movement_move_asked.write(writer, variant)
    MoveDefault(variant) -> movement_kind_13.write(writer, variant)
    Rotation(variant) -> movement_rotation.write(writer, variant)
    FaceUnit(variant) -> movement_face_unit.write(writer, variant)
    FacePoint(variant) -> movement_face_point.write(writer, variant)
    RotationDefault(variant) -> movement_kind_21.write(writer, variant)
    StateFlags(variant) -> movement_state_flags.write(writer, variant)
    StateDefault(variant) -> movement_kind_26.write(writer, variant)
    Mode(variant) -> movement_mode.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(RelayedMovement, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 5))
  case kind {
    0 -> reader |> movement_time.read |> result.map(pair.map_first(_, Time))
    1 ->
      reader
      |> movement_platform.read
      |> result.map(pair.map_first(_, Platform))
    2 ->
      reader
      |> unit_position_command.read
      |> result.map(pair.map_first(_, Position))
    3 ->
      reader
      |> movement_timed_path.read
      |> result.map(pair.map_first(_, TimedPath))
    4 -> reader |> movement_path.read |> result.map(pair.map_first(_, Path))
    8 ->
      reader
      |> movement_velocity.read
      |> result.map(pair.map_first(_, Velocity))
    10 ->
      reader
      |> movement_kind_10.read
      |> result.map(pair.map_first(_, VelocityDefault))
    11 ->
      reader
      |> movement_move_asked.read
      |> result.map(pair.map_first(_, MoveAsked))
    13 ->
      reader
      |> movement_kind_13.read
      |> result.map(pair.map_first(_, MoveDefault))
    14 ->
      reader
      |> movement_rotation.read
      |> result.map(pair.map_first(_, Rotation))
    18 ->
      reader
      |> movement_face_unit.read
      |> result.map(pair.map_first(_, FaceUnit))
    19 ->
      reader
      |> movement_face_point.read
      |> result.map(pair.map_first(_, FacePoint))
    21 ->
      reader
      |> movement_kind_21.read
      |> result.map(pair.map_first(_, RotationDefault))
    24 ->
      reader
      |> movement_state_flags.read
      |> result.map(pair.map_first(_, StateFlags))
    26 ->
      reader
      |> movement_kind_26.read
      |> result.map(pair.map_first(_, StateDefault))
    27 -> reader |> movement_mode.read |> result.map(pair.map_first(_, Mode))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "relayed_movement", value: kind))
  }
}
