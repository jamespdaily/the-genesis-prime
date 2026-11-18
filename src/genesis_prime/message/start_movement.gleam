//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one movement command of a new unit that the
//// server writes: the kind in 5 bits picks the layout of its data, and the
//// server writes only kind 2, the position, and kind 14, the rotation; the
//// client's reader takes all 30 kinds (movement_command). Its variants are
//// listed in `schema.toml` with the client's evidence, and the fact file's
//// `0x140c1f070` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_rotation.{type MovementRotation}
import genesis_prime/message/unit_position_command.{type UnitPositionCommand}
import gleam/pair
import gleam/result

/// One item of the union: its first 5 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
///
/// These kinds are open, so no variant holds them and a read refuses them: 0
/// (What makes the server send kind 0 (time) in a new unit's command list?
/// Candidate: a new unit's later commands apply at a server time.) (layout so
/// far in the fact file's `movement_command.kind_0`); 1 (What makes the server
/// send kind 1 (platform) in a new unit's command list? Candidate: a new unit
/// stands on another unit.) (layout so far in the fact file's `opcode.0x637`);
/// 3 (What makes the server send kind 3 (timed path) in a new unit's command
/// list? Candidate: a new unit follows a path timed in server time.) (layout so
/// far in the fact file's `movement_command.kind_3`); 4 (What makes the server
/// send kind 4 (path) in a new unit's command list? Candidate: a new unit
/// follows a path of points at a speed.) (layout so far in the fact file's
/// `movement_command.kind_4`); 5 (What makes the server send kind 5 (one
/// authored spline) in a new unit's command list? Candidate: a new unit follows
/// one Spline2 spline, a patrol (a guess).) (layout so far in the fact file's
/// `movement_command.kind_5`); 6 (What makes the server send kind 6 (a chain of
/// authored splines) in a new unit's command list? Candidate: a new unit flies
/// a chain of Spline2 splines, as a taxi does (a guess).) (layout so far in the
/// fact file's `movement_command.kind_6`); 7 (What makes the server send kind 7
/// (a ballistic arc) in a new unit's command list? Candidate: a unit leaps or
/// is thrown along an arc to a point.) (layout so far in the fact file's
/// `movement_command.kind_7`); 8 (What makes the server send kind 8 (velocity)
/// in a new unit's command list? Candidate: a new unit has a velocity.) (layout
/// so far in the fact file's `movement_command.kind_8`); 9 (What makes the
/// server send kind 9 (timed velocity keys) in a new unit's command list?
/// Candidate: a unit's velocity is keyed in time, which kind 10 covers for a
/// path.) (layout so far in the fact file's `0x140c1f070`); 10 (What makes the
/// server send kind 10 (velocity default) in a new unit's command list?
/// Candidate: a new unit's velocity follows its position path.) (layout so far
/// in the fact file's `movement_command.defaults_with_kind_4_path`); 11 (What
/// makes the server send kind 11 (move asked) in a new unit's command list?
/// Candidate: a new unit has a requested move.) (layout so far in the fact
/// file's `movement_command.kind_11`); 12 (What makes the server send kind 12
/// (timed requested-move keys) in a new unit's command list? Candidate: a
/// unit's requested move is keyed in time, which kind 13 covers for a path.)
/// (layout so far in the fact file's `0x140c1f070`); 13 (What makes the server
/// send kind 13 (move default) in a new unit's command list? Candidate: a new
/// unit's requested move follows its position path.) (layout so far in the fact
/// file's `movement_command.kind_13`); 15 (What makes the server send kind 15
/// (timed rotation keys) in a new unit's command list? Candidate: a unit's
/// rotation is keyed in time, which kinds 14, 18 and 21 cover.) (layout so far
/// in the fact file's `0x140c1f070`); 16 (What makes the server send kind 16
/// (rotation along one spline) in a new unit's command list? Candidate: a
/// unit's rotation follows one Spline2 spline, as a pair of kind 5 (a guess).)
/// (layout so far in the fact file's `0x140c1f070`); 17 (What makes the server
/// send kind 17 (rotation along a chain of splines) in a new unit's command
/// list? Candidate: a unit's rotation follows a chain of Spline2 splines, as a
/// pair of kind 6 (a guess).) (layout so far in the fact file's `0x140c1f070`);
/// 18 (What makes the server send kind 18 (face a unit) in a new unit's command
/// list? Candidate: a new unit turns to face another unit.) (layout so far in
/// the fact file's `movement_command.kind_18`); 19 (What makes the server send
/// kind 19 (face a point) in a new unit's command list? Candidate: a new unit
/// turns to face a point.) (layout so far in the fact file's
/// `movement_command.kind_19`); 20 (What makes the server send kind 20 (spin)
/// in a new unit's command list? Candidate: a unit spins, as a whirlwind attack
/// does.) (layout so far in the fact file's `movement_command.kind_20`); 21
/// (What makes the server send kind 21 (rotation default) in a new unit's
/// command list? Candidate: a new unit's rotation follows its position path.)
/// (layout so far in the fact file's `movement_command.kind_21`); 22 (What
/// makes the server send kind 22 (movement scale) in a new unit's command list?
/// Candidate: a unit grows or shrinks.) (layout so far in the fact file's
/// `movement_command.kind_22`); 23 (What makes the server send kind 23 (timed
/// movement scale keys) in a new unit's command list? Candidate: a unit's
/// growing or shrinking is keyed in time.) (layout so far in the fact file's
/// `movement_command.kind_22`); 24 (What makes the server send kind 24 (state
/// flags) in a new unit's command list? Candidate: a new unit has movement
/// state flags.) (layout so far in the fact file's `movement_command.kind_24`);
/// 25 (What makes the server send kind 25 (timed state flags) in a new unit's
/// command list? Candidate: a unit's state flags are keyed in time, as a kind 3
/// flight does.) (layout so far in the fact file's `movement_command.kind_25`);
/// 26 (What makes the server send kind 26 (state default) in a new unit's
/// command list? Candidate: a new unit's state flags follow its position path.)
/// (layout so far in the fact file's
/// `movement_command.defaults_with_kind_4_path`); 27 (What makes the server
/// send kind 27 (mode) in a new unit's command list? Candidate: a new unit has
/// a movement mode.) (layout so far in the fact file's
/// `movement_command.kind_27`); 28 (What makes the server send kind 28 (timed
/// movement modes) in a new unit's command list? Candidate: a unit's mode
/// changes along a kind 3 flight.) (layout so far in the fact file's
/// `0x140c1f070`); 29 (What makes the server send kind 29 (mode default) in a
/// new unit's command list? Candidate: a unit's mode is 0 on every update, the
/// same as kind 27 of 0.) (layout so far in the fact file's `0x1407168f0`).
pub type StartMovement {
  /// Kind 2, read by `unit_position_command`. The fact file's `0x1400ad350`
  /// names the kind.
  Position(UnitPositionCommand)
  /// Kind 14, read by `movement_rotation`. The fact file's `0x140715350` names
  /// the kind.
  Rotation(MovementRotation)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: StartMovement) -> Writer {
  case record {
    Position(variant) -> unit_position_command.write(writer, variant)
    Rotation(variant) -> movement_rotation.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(StartMovement, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 5))
  case kind {
    2 ->
      reader
      |> unit_position_command.read
      |> result.map(pair.map_first(_, Position))
    14 ->
      reader
      |> movement_rotation.read
      |> result.map(pair.map_first(_, Rotation))
    _ -> Error(bit_stream.UnexpectedValue(field: "start_movement", value: kind))
  }
}
