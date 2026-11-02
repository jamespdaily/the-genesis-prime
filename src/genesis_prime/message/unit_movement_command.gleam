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
pub type UnitMovementCommand {
  /// Kind 2, read by `unit_position_command`. The fact file's `0x1400ad350`
  /// names the kind.
  Position(UnitPositionCommand)
  /// Kind 14, read by `movement_rotation`. The fact file's `0x140715350` names
  /// the kind.
  Rotation(MovementRotation)
}

/// Writes the variant's record to the stream.
pub fn write(
  writer writer: Writer,
  record record: UnitMovementCommand,
) -> Writer {
  case record {
    Position(variant) -> unit_position_command.write(writer, variant)
    Rotation(variant) -> movement_rotation.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(
  reader: Reader,
) -> Result(#(UnitMovementCommand, Reader), DecodeError) {
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
    _ ->
      Error(bit_stream.UnexpectedValue(
        field: "unit_movement_command",
        value: kind,
      ))
  }
}
