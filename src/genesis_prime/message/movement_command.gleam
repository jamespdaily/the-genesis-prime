//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one movement command: the kind in 5 bits
//// picks the layout of its data, and the client's reader refuses a kind of 30
//// or 31. Its variants are listed in `schema.toml` with the client's evidence,
//// and the fact file's `0x140c1f070` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/movement_kind_10.{type MovementKind10}
import genesis_prime/message/movement_kind_12.{type MovementKind12}
import genesis_prime/message/movement_kind_13.{type MovementKind13}
import genesis_prime/message/movement_kind_15.{type MovementKind15}
import genesis_prime/message/movement_kind_16.{type MovementKind16}
import genesis_prime/message/movement_kind_17.{type MovementKind17}
import genesis_prime/message/movement_kind_18.{type MovementKind18}
import genesis_prime/message/movement_kind_19.{type MovementKind19}
import genesis_prime/message/movement_kind_20.{type MovementKind20}
import genesis_prime/message/movement_kind_21.{type MovementKind21}
import genesis_prime/message/movement_kind_22.{type MovementKind22}
import genesis_prime/message/movement_kind_23.{type MovementKind23}
import genesis_prime/message/movement_kind_25.{type MovementKind25}
import genesis_prime/message/movement_kind_26.{type MovementKind26}
import genesis_prime/message/movement_kind_28.{type MovementKind28}
import genesis_prime/message/movement_kind_29.{type MovementKind29}
import genesis_prime/message/movement_kind_3.{type MovementKind3}
import genesis_prime/message/movement_kind_4.{type MovementKind4}
import genesis_prime/message/movement_kind_5.{type MovementKind5}
import genesis_prime/message/movement_kind_6.{type MovementKind6}
import genesis_prime/message/movement_kind_7.{type MovementKind7}
import genesis_prime/message/movement_kind_9.{type MovementKind9}
import genesis_prime/message/movement_mode.{type MovementMode}
import genesis_prime/message/movement_move_asked.{type MovementMoveAsked}
import genesis_prime/message/movement_platform.{type MovementPlatform}
import genesis_prime/message/movement_rotation.{type MovementRotation}
import genesis_prime/message/movement_state_flags.{type MovementStateFlags}
import genesis_prime/message/movement_time.{type MovementTime}
import genesis_prime/message/movement_velocity.{type MovementVelocity}
import genesis_prime/message/unit_position_command.{type UnitPositionCommand}
import gleam/pair
import gleam/result

/// One item of the union: its first 5 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type MovementCommand {
  /// Kind 0, read by `movement_time`. The fact file's `movement_command.kind_0`
  /// names the kind.
  Time(MovementTime)
  /// Kind 1, read by `movement_platform`. The fact file's `opcode.0x637` names
  /// the kind.
  Platform(MovementPlatform)
  /// Kind 2, read by `unit_position_command`. The fact file's `0x1400ad350`
  /// names the kind.
  Position(UnitPositionCommand)
  /// Kind 3, read by `movement_kind_3`.
  Kind3(MovementKind3)
  /// Kind 4, read by `movement_kind_4`.
  Kind4(MovementKind4)
  /// Kind 5, read by `movement_kind_5`.
  Kind5(MovementKind5)
  /// Kind 6, read by `movement_kind_6`.
  Kind6(MovementKind6)
  /// Kind 7, read by `movement_kind_7`.
  Kind7(MovementKind7)
  /// Kind 8, read by `movement_velocity`. The fact file's
  /// `movement_command.kind_8` names the kind.
  Velocity(MovementVelocity)
  /// Kind 9, read by `movement_kind_9`.
  Kind9(MovementKind9)
  /// Kind 10, read by `movement_kind_10`.
  Kind10(MovementKind10)
  /// Kind 11, read by `movement_move_asked`. The fact file's
  /// `movement_command.kind_11` names the kind.
  MoveAsked(MovementMoveAsked)
  /// Kind 12, read by `movement_kind_12`.
  Kind12(MovementKind12)
  /// Kind 13, read by `movement_kind_13`.
  Kind13(MovementKind13)
  /// Kind 14, read by `movement_rotation`. The fact file's `0x140715350` names
  /// the kind.
  Rotation(MovementRotation)
  /// Kind 15, read by `movement_kind_15`.
  Kind15(MovementKind15)
  /// Kind 16, read by `movement_kind_16`.
  Kind16(MovementKind16)
  /// Kind 17, read by `movement_kind_17`.
  Kind17(MovementKind17)
  /// Kind 18, read by `movement_kind_18`.
  Kind18(MovementKind18)
  /// Kind 19, read by `movement_kind_19`.
  Kind19(MovementKind19)
  /// Kind 20, read by `movement_kind_20`.
  Kind20(MovementKind20)
  /// Kind 21, read by `movement_kind_21`.
  Kind21(MovementKind21)
  /// Kind 22, read by `movement_kind_22`.
  Kind22(MovementKind22)
  /// Kind 23, read by `movement_kind_23`.
  Kind23(MovementKind23)
  /// Kind 24, read by `movement_state_flags`. The fact file's
  /// `movement_command.kind_24` names the kind.
  StateFlags(MovementStateFlags)
  /// Kind 25, read by `movement_kind_25`.
  Kind25(MovementKind25)
  /// Kind 26, read by `movement_kind_26`.
  Kind26(MovementKind26)
  /// Kind 27, read by `movement_mode`. The fact file's
  /// `movement_command.kind_27` names the kind.
  Mode(MovementMode)
  /// Kind 28, read by `movement_kind_28`.
  Kind28(MovementKind28)
  /// Kind 29, read by `movement_kind_29`.
  Kind29(MovementKind29)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: MovementCommand) -> Writer {
  case record {
    Time(variant) -> movement_time.write(writer, variant)
    Platform(variant) -> movement_platform.write(writer, variant)
    Position(variant) -> unit_position_command.write(writer, variant)
    Kind3(variant) -> movement_kind_3.write(writer, variant)
    Kind4(variant) -> movement_kind_4.write(writer, variant)
    Kind5(variant) -> movement_kind_5.write(writer, variant)
    Kind6(variant) -> movement_kind_6.write(writer, variant)
    Kind7(variant) -> movement_kind_7.write(writer, variant)
    Velocity(variant) -> movement_velocity.write(writer, variant)
    Kind9(variant) -> movement_kind_9.write(writer, variant)
    Kind10(variant) -> movement_kind_10.write(writer, variant)
    MoveAsked(variant) -> movement_move_asked.write(writer, variant)
    Kind12(variant) -> movement_kind_12.write(writer, variant)
    Kind13(variant) -> movement_kind_13.write(writer, variant)
    Rotation(variant) -> movement_rotation.write(writer, variant)
    Kind15(variant) -> movement_kind_15.write(writer, variant)
    Kind16(variant) -> movement_kind_16.write(writer, variant)
    Kind17(variant) -> movement_kind_17.write(writer, variant)
    Kind18(variant) -> movement_kind_18.write(writer, variant)
    Kind19(variant) -> movement_kind_19.write(writer, variant)
    Kind20(variant) -> movement_kind_20.write(writer, variant)
    Kind21(variant) -> movement_kind_21.write(writer, variant)
    Kind22(variant) -> movement_kind_22.write(writer, variant)
    Kind23(variant) -> movement_kind_23.write(writer, variant)
    StateFlags(variant) -> movement_state_flags.write(writer, variant)
    Kind25(variant) -> movement_kind_25.write(writer, variant)
    Kind26(variant) -> movement_kind_26.write(writer, variant)
    Mode(variant) -> movement_mode.write(writer, variant)
    Kind28(variant) -> movement_kind_28.write(writer, variant)
    Kind29(variant) -> movement_kind_29.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(MovementCommand, Reader), DecodeError) {
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
    3 -> reader |> movement_kind_3.read |> result.map(pair.map_first(_, Kind3))
    4 -> reader |> movement_kind_4.read |> result.map(pair.map_first(_, Kind4))
    5 -> reader |> movement_kind_5.read |> result.map(pair.map_first(_, Kind5))
    6 -> reader |> movement_kind_6.read |> result.map(pair.map_first(_, Kind6))
    7 -> reader |> movement_kind_7.read |> result.map(pair.map_first(_, Kind7))
    8 ->
      reader
      |> movement_velocity.read
      |> result.map(pair.map_first(_, Velocity))
    9 -> reader |> movement_kind_9.read |> result.map(pair.map_first(_, Kind9))
    10 ->
      reader
      |> movement_kind_10.read
      |> result.map(pair.map_first(_, Kind10))
    11 ->
      reader
      |> movement_move_asked.read
      |> result.map(pair.map_first(_, MoveAsked))
    12 ->
      reader
      |> movement_kind_12.read
      |> result.map(pair.map_first(_, Kind12))
    13 ->
      reader
      |> movement_kind_13.read
      |> result.map(pair.map_first(_, Kind13))
    14 ->
      reader
      |> movement_rotation.read
      |> result.map(pair.map_first(_, Rotation))
    15 ->
      reader
      |> movement_kind_15.read
      |> result.map(pair.map_first(_, Kind15))
    16 ->
      reader
      |> movement_kind_16.read
      |> result.map(pair.map_first(_, Kind16))
    17 ->
      reader
      |> movement_kind_17.read
      |> result.map(pair.map_first(_, Kind17))
    18 ->
      reader
      |> movement_kind_18.read
      |> result.map(pair.map_first(_, Kind18))
    19 ->
      reader
      |> movement_kind_19.read
      |> result.map(pair.map_first(_, Kind19))
    20 ->
      reader
      |> movement_kind_20.read
      |> result.map(pair.map_first(_, Kind20))
    21 ->
      reader
      |> movement_kind_21.read
      |> result.map(pair.map_first(_, Kind21))
    22 ->
      reader
      |> movement_kind_22.read
      |> result.map(pair.map_first(_, Kind22))
    23 ->
      reader
      |> movement_kind_23.read
      |> result.map(pair.map_first(_, Kind23))
    24 ->
      reader
      |> movement_state_flags.read
      |> result.map(pair.map_first(_, StateFlags))
    25 ->
      reader
      |> movement_kind_25.read
      |> result.map(pair.map_first(_, Kind25))
    26 ->
      reader
      |> movement_kind_26.read
      |> result.map(pair.map_first(_, Kind26))
    27 -> reader |> movement_mode.read |> result.map(pair.map_first(_, Mode))
    28 ->
      reader
      |> movement_kind_28.read
      |> result.map(pair.map_first(_, Kind28))
    29 ->
      reader
      |> movement_kind_29.read
      |> result.map(pair.map_first(_, Kind29))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "movement_command", value: kind))
  }
}
