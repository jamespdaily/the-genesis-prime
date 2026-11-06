//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: the stat of a 0x938 in 5 bits picks the
//// layout of its value. Gap: the schema holds stats 20 and 21; the client's
//// ApplyUnitStat takes others too (10, 22), which the server never writes. Its
//// variants are listed in `schema.toml` with the client's evidence, and the
//// fact file's `opcode.0x938` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/unit_stat_interrupt_armor.{
  type UnitStatInterruptArmor,
}
import genesis_prime/message/unit_stat_shield.{type UnitStatShield}
import gleam/pair
import gleam/result

/// One item of the union: its first 5 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type UnitStatChange {
  /// Kind 20, read by `unit_stat_shield`. The fact file's
  /// `opcode.0x938.resource_stats` names the kind.
  Shield(UnitStatShield)
  /// Kind 21, read by `unit_stat_interrupt_armor`. The fact file's
  /// `opcode.0x938.interrupt_armor` names the kind.
  InterruptArmor(UnitStatInterruptArmor)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: UnitStatChange) -> Writer {
  case record {
    Shield(variant) -> unit_stat_shield.write(writer, variant)
    InterruptArmor(variant) -> unit_stat_interrupt_armor.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(UnitStatChange, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 5))
  case kind {
    20 ->
      reader
      |> unit_stat_shield.read
      |> result.map(pair.map_first(_, Shield))
    21 ->
      reader
      |> unit_stat_interrupt_armor.read
      |> result.map(pair.map_first(_, InterruptArmor))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "unit_stat_change", value: kind))
  }
}
