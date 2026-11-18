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
///
/// The client reads these kinds and the server never sends them, so no variant
/// holds them and a read refuses them: 1 float_stat_0x218 (the fact file's
/// `opcode.0x938.all_stats`), 2 resource_slot_0 (the fact file's
/// `opcode.0x938.all_stats`), 3 resource_slot_1 (the fact file's
/// `opcode.0x938.all_stats`), 4 resource_slot_2 (the fact file's
/// `opcode.0x938.all_stats`), 5 resource_slot_3 (the fact file's
/// `opcode.0x938.all_stats`), 6 resource_slot_4 (the fact file's
/// `opcode.0x938.all_stats`), 7 resource_slot_5 (the fact file's
/// `opcode.0x938.all_stats`), 8 resource_slot_6 (the fact file's
/// `opcode.0x938.all_stats`), 9 resource_slot_7 (the fact file's
/// `opcode.0x938.all_stats`), 12 unread_12 (the fact file's
/// `opcode.0x938.all_stats`), 13 unread_13 (the fact file's
/// `opcode.0x938.all_stats`), 14 unread_14 (the fact file's
/// `opcode.0x938.all_stats`), 16 unread_16 (the fact file's
/// `opcode.0x938.all_stats`), 18 unread_18 (the fact file's
/// `opcode.0x938.all_stats`), 19 float_stat_slot_0x68 (the fact file's
/// `opcode.0x938.all_stats`), 23 float_stat_0x23c (the fact file's
/// `opcode.0x938.all_stats`), 24 float_stat_0x240 (the fact file's
/// `opcode.0x938.all_stats`), 25 float_stat_0x244 (the fact file's
/// `opcode.0x938.all_stats`), 27 unread_27 (the fact file's
/// `opcode.0x938.all_stats`), 28 unread_28 (the fact file's
/// `opcode.0x938.all_stats`), 29 unread_29 (the fact file's
/// `opcode.0x938.all_stats`), 30 unread_30 (the fact file's
/// `opcode.0x938.all_stats`), 31 unread_31 (the fact file's
/// `opcode.0x938.all_stats`).
///
/// These kinds are open, so no variant holds them and a read refuses them: 0
/// (health: what builds it: the client sets no health from it, but for the
/// player's own unit raises UI_HealthChanged with the value and the unit's real
/// health; when that notification is needed is not settled) (layout so far in
/// the fact file's `opcode.0x938.all_stats`); 11 (effective_level: what builds
/// it: mentoring, which is not built; the name MentorLevel is a lead from the
/// earlier server, not the client's) (layout so far in the fact file's
/// `opcode.0x938.all_stats`); 15 (sheathed: what builds it: creatures drawing
/// weapons at a fight start, a guess; a recording of a fight start settles it;
/// the name is a lead from the earlier server, not the client's) (layout so far
/// in the fact file's `opcode.0x938.all_stats`); 17 (cluster: what builds it:
/// unit clusters, which are not built) (layout so far in the fact file's
/// `opcode.0x938.all_stats`); 26 (integer stored at unit 0x50: what builds it:
/// nothing is known, the client does not read its meaning) (layout so far in
/// the fact file's `opcode.0x938.all_stats`).
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
