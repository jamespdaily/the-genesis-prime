//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: the stat of a 0x938 in 5 bits picks the
//// layout of its value. Its variants are listed in `schema.toml` with the
//// client's evidence, and the fact file's `opcode.0x938` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/unit_stat_absorption.{type UnitStatAbsorption}
import genesis_prime/message/unit_stat_interrupt_armor.{
  type UnitStatInterruptArmor,
}
import genesis_prime/message/unit_stat_level.{type UnitStatLevel}
import genesis_prime/message/unit_stat_shield.{type UnitStatShield}
import gleam/pair
import gleam/result

/// One item of the union: its first 5 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type UnitStatChange {
  /// Kind 10, read by `unit_stat_level`. The fact file's `opcode.0x938` names
  /// the kind.
  Level(UnitStatLevel)
  /// Kind 20, read by `unit_stat_shield`. The fact file's
  /// `opcode.0x938.resource_stats` names the kind.
  Shield(UnitStatShield)
  /// Kind 21, read by `unit_stat_interrupt_armor`. The fact file's
  /// `opcode.0x938.interrupt_armor` names the kind.
  InterruptArmor(UnitStatInterruptArmor)
  /// Kind 22, read by `unit_stat_absorption`. The fact file's `opcode.0x938`
  /// names the kind.
  Absorption(UnitStatAbsorption)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: UnitStatChange) -> Writer {
  case record {
    Level(variant) -> unit_stat_level.write(writer, variant)
    Shield(variant) -> unit_stat_shield.write(writer, variant)
    InterruptArmor(variant) -> unit_stat_interrupt_armor.write(writer, variant)
    Absorption(variant) -> unit_stat_absorption.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitStatChange, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 5))
  case kind {
    10 -> reader |> unit_stat_level.read |> result.map(pair.map_first(_, Level))
    20 ->
      reader
      |> unit_stat_shield.read
      |> result.map(pair.map_first(_, Shield))
    21 ->
      reader
      |> unit_stat_interrupt_armor.read
      |> result.map(pair.map_first(_, InterruptArmor))
    22 ->
      reader
      |> unit_stat_absorption.read
      |> result.map(pair.map_first(_, Absorption))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "unit_stat_change", value: kind))
  }
}
