//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one movement command of a new unit that the
//// server writes: the kind in 5 bits picks the layout of its data, and the
//// server writes only kind 2, the position, and kind 14, the rotation; kinds
//// 0, 1, 3, 4, 8, 10, 11, 13, 18, 19, 21, 24, 26 and 27 share the layouts of
//// the relayed movement commands, and the client's reader takes all 30 kinds
//// (movement_command). Its variants are listed in `schema.toml` with the
//// client's evidence, and the fact file's `0x140c1f070` names the union.

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
///
/// These kinds are open, so no variant holds them and a read refuses them: 5
/// (What makes the server send kind 5 (one authored spline) in a new unit's
/// command list? Candidate: a new unit follows one Spline2 spline, a patrol (a
/// guess).) (layout so far in the fact file's `movement_command.kind_5`); 6
/// (What makes the server send kind 6 (a chain of authored splines) in a new
/// unit's command list? Candidate: a new unit flies a chain of Spline2 splines,
/// as a taxi does (a guess).) (layout so far in the fact file's
/// `movement_command.kind_6`); 7 (What makes the server send kind 7 (a
/// ballistic arc) in a new unit's command list? Candidate: a unit leaps or is
/// thrown along an arc to a point.) (layout so far in the fact file's
/// `movement_command.kind_7`); 9 (What makes the server send kind 9 (timed
/// velocity keys) in a new unit's command list? Candidate: a unit's velocity is
/// keyed in time, which kind 10 covers for a path.) (layout so far in the fact
/// file's `0x140c1f070`); 12 (What makes the server send kind 12 (timed
/// requested-move keys) in a new unit's command list? Candidate: a unit's
/// requested move is keyed in time, which kind 13 covers for a path.) (layout
/// so far in the fact file's `0x140c1f070`); 15 (What makes the server send
/// kind 15 (timed rotation keys) in a new unit's command list? Candidate: a
/// unit's rotation is keyed in time, which kinds 14, 18 and 21 cover.) (layout
/// so far in the fact file's `0x140c1f070`); 16 (What makes the server send
/// kind 16 (rotation along one spline) in a new unit's command list? Candidate:
/// a unit's rotation follows one Spline2 spline, as a pair of kind 5 (a
/// guess).) (layout so far in the fact file's `0x140c1f070`); 17 (What makes
/// the server send kind 17 (rotation along a chain of splines) in a new unit's
/// command list? Candidate: a unit's rotation follows a chain of Spline2
/// splines, as a pair of kind 6 (a guess).) (layout so far in the fact file's
/// `0x140c1f070`); 20 (What makes the server send kind 20 (spin) in a new
/// unit's command list? Candidate: a unit spins, as a whirlwind attack does.)
/// (layout so far in the fact file's `movement_command.kind_20`); 22 (What
/// makes the server send kind 22 (movement scale) in a new unit's command list?
/// Candidate: a unit grows or shrinks.) (layout so far in the fact file's
/// `movement_command.kind_22`); 23 (What makes the server send kind 23 (timed
/// movement scale keys) in a new unit's command list? Candidate: a unit's
/// growing or shrinking is keyed in time.) (layout so far in the fact file's
/// `movement_command.kind_22`); 25 (What makes the server send kind 25 (timed
/// state flags) in a new unit's command list? Candidate: a unit's state flags
/// are keyed in time, as a kind 3 flight does.) (layout so far in the fact
/// file's `movement_command.kind_25`); 28 (What makes the server send kind 28
/// (timed movement modes) in a new unit's command list? Candidate: a unit's
/// mode changes along a kind 3 flight.) (layout so far in the fact file's
/// `0x140c1f070`); 29 (What makes the server send kind 29 (mode default) in a
/// new unit's command list? Candidate: a unit's mode is 0 on every update, the
/// same as kind 27 of 0. The wire carries one bit after the tag (0x140c1f070
/// entry 29); the handler 0x1407168f0 takes no data.) (layout so far in the
/// fact file's `0x140c1f070`).
pub type StartMovement {
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
pub fn write(writer writer: Writer, record record: StartMovement) -> Writer {
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
pub fn read(reader: Reader) -> Result(#(StartMovement, Reader), DecodeError) {
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
    _ -> Error(bit_stream.UnexpectedValue(field: "start_movement", value: kind))
  }
}
