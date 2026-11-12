//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one entry of the combat log: the type in 6
//// bits picks the layout of its data. Gap: the schema holds types 1, 2, 18,
//// 22, 23 and 24, and the client's reader takes 0 to 35; the other types are
//// open under issue 336, spells work in depth on the real client. Its variants
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x247` names the union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/combat_log_cc_state.{type CombatLogCcState}
import genesis_prime/message/combat_log_cc_state_break.{
  type CombatLogCcStateBreak,
}
import genesis_prime/message/combat_log_death.{type CombatLogDeath}
import genesis_prime/message/combat_log_immunity.{type CombatLogImmunity}
import genesis_prime/message/combat_log_resurrect.{type CombatLogResurrect}
import genesis_prime/message/combat_log_stealth.{type CombatLogStealth}
import gleam/pair
import gleam/result

/// One item of the union: its first 6 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
pub type CombatLogEntry {
  /// Kind 1, read by `combat_log_cc_state`. The fact file's
  /// `opcode.0x247.cc_state` names the kind.
  CcState(CombatLogCcState)
  /// Kind 2, read by `combat_log_cc_state_break`. The fact file's
  /// `opcode.0x247.cc_state` names the kind.
  CcStateBreak(CombatLogCcStateBreak)
  /// Kind 18, read by `combat_log_immunity`. The fact file's
  /// `opcode.0x247.immunity` names the kind.
  Immunity(CombatLogImmunity)
  /// Kind 22, read by `combat_log_death`. The fact file's `opcode.0x247.death`
  /// names the kind.
  Death(CombatLogDeath)
  /// Kind 23, read by `combat_log_resurrect`. The fact file's
  /// `opcode.0x247.death` names the kind.
  Resurrect(CombatLogResurrect)
  /// Kind 24, read by `combat_log_stealth`. The fact file's
  /// `opcode.0x247.type24` names the kind.
  Stealth(CombatLogStealth)
}

/// Writes the variant's record to the stream.
pub fn write(writer writer: Writer, record record: CombatLogEntry) -> Writer {
  case record {
    CcState(variant) -> combat_log_cc_state.write(writer, variant)
    CcStateBreak(variant) -> combat_log_cc_state_break.write(writer, variant)
    Immunity(variant) -> combat_log_immunity.write(writer, variant)
    Death(variant) -> combat_log_death.write(writer, variant)
    Resurrect(variant) -> combat_log_resurrect.write(writer, variant)
    Stealth(variant) -> combat_log_stealth.write(writer, variant)
  }
}

/// Reads the item from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(CombatLogEntry, Reader), DecodeError) {
  use kind <- result.try(bit_stream.peek_unsigned(reader, 6))
  case kind {
    1 ->
      reader
      |> combat_log_cc_state.read
      |> result.map(pair.map_first(_, CcState))
    2 ->
      reader
      |> combat_log_cc_state_break.read
      |> result.map(pair.map_first(_, CcStateBreak))
    18 ->
      reader
      |> combat_log_immunity.read
      |> result.map(pair.map_first(_, Immunity))
    22 ->
      reader
      |> combat_log_death.read
      |> result.map(pair.map_first(_, Death))
    23 ->
      reader
      |> combat_log_resurrect.read
      |> result.map(pair.map_first(_, Resurrect))
    24 ->
      reader
      |> combat_log_stealth.read
      |> result.map(pair.map_first(_, Stealth))
    _ ->
      Error(bit_stream.UnexpectedValue(field: "combat_log_entry", value: kind))
  }
}
