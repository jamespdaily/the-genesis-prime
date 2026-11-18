//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A union inside a message body: one entry of the combat log: the type in 6
//// bits picks the layout of its data. Its variants are listed in `schema.toml`
//// with the client's evidence, and the fact file's `opcode.0x247` names the
//// union.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/combat_log_cc_state.{type CombatLogCcState}
import genesis_prime/message/combat_log_cc_state_break.{
  type CombatLogCcStateBreak,
}
import genesis_prime/message/combat_log_death.{type CombatLogDeath}
import genesis_prime/message/combat_log_immunity.{type CombatLogImmunity}
import genesis_prime/message/combat_log_modify_interrupt_armor.{
  type CombatLogModifyInterruptArmor,
}
import genesis_prime/message/combat_log_resurrect.{type CombatLogResurrect}
import genesis_prime/message/combat_log_stealth.{type CombatLogStealth}
import gleam/pair
import gleam/result

/// One item of the union: its first 6 bits are its kind, which picks the
/// variant, and the variant's record reads them again as its first field. A
/// kind no variant has is refused.
///
/// The client reads these kinds and the server never sends them, so no variant
/// holds them and a read refuses them: 3 damage (the fact file's
/// `opcode.0x247.damage`), 4 damage_shields (the fact file's
/// `opcode.0x247.damage_shields`), 6 multi_hit (the fact file's
/// `opcode.0x247.multi_hit`), 7 multi_hit_shields (the fact file's
/// `opcode.0x247.multi_hit_shields`), 12 heal (the fact file's
/// `opcode.0x247.heal`), 13 multi_heal (the fact file's
/// `opcode.0x247.multi_heal`), 17 deflect (the fact file's
/// `opcode.0x247.deflect`), 34 unhandled_34 (the fact file's
/// `opcode.0x247.unhandled_34`).
///
/// These kinds are open, so no variant holds them and a read refuses them: 0
/// (absorption: what builds it: a spell that grants an absorption pool, which
/// no other message logs) (layout so far in the fact file's
/// `opcode.0x247.absorption`); 5 (reflect: what builds it: a reflect effect,
/// none is built; which of its two bits is vulnerable and which is killed is
/// not read) (layout so far in the fact file's `opcode.0x247.reflect`); 8
/// (falling_damage: what builds it: falling damage, which the server does not
/// handle) (layout so far in the fact file's `opcode.0x247.falling_damage`); 9
/// (life_steal: what builds it: a life-steal effect, none is built; the order
/// of its two amounts is read from the copy order only) (layout so far in the
/// fact file's `opcode.0x247.life_steal`); 10 (delay_death: what builds it: a
/// delay-death effect, none is built) (layout so far in the fact file's
/// `opcode.0x247.delay_death`); 11 (dispel: what builds it: a dispel effect,
/// none is built) (layout so far in the fact file's `opcode.0x247.dispel`); 15
/// (transference: what builds it: a transference effect, none is built; its
/// 3-bit value and four amounts are named only by analogy with type 3) (layout
/// so far in the fact file's `opcode.0x247.transference`); 16 (vital_modifier:
/// what builds it: the resource gains of spells are built and only this type
/// logs them; did retail set bShowCombatLog for them (a recording of a resource
/// gain settles it)) (layout so far in the fact file's
/// `opcode.0x247.vital_modifier`); 19 (interrupted: what builds it: casts are
/// interrupted and only this type logs it; which of its cast-data units is the
/// interrupter is not read) (layout so far in the fact file's
/// `opcode.0x247.interrupted`); 20 (kill_streak: what builds it: kill streaks,
/// which only PvP raises) (layout so far in the fact file's
/// `opcode.0x247.kill_streak`); 21 (kill_pvp: what builds it: PvP kill assists)
/// (layout so far in the fact file's `opcode.0x247.kill_pvp`); 25 (mount: what
/// builds it: mounting and dismounting, which are not built) (layout so far in
/// the fact file's `opcode.0x247.mount`); 26 (pet: what builds it: summoning,
/// dismissing and losing a pet, which are not built) (layout so far in the fact
/// file's `opcode.0x247.pet`); 27 (experience: what builds it: elder points
/// only, as the experience line is already printed from the experience message;
/// the order of its four amounts is taken from the Lua handler) (layout so far
/// in the fact file's `opcode.0x247.experience`); 28 (modifying: what builds
/// it: item modification (runes), which is not built) (layout so far in the
/// fact file's `opcode.0x247.modifying`); 29 (durability_loss: what builds it:
/// durability loss, which is not built) (layout so far in the fact file's
/// `opcode.0x247.durability_loss`); 30 (item_destroy: what builds it: deleting
/// an item, the only way the client prints the destroy line; that retail sent
/// it after the item delete message is inferred, not recorded) (layout so far
/// in the fact file's `opcode.0x247.item_destroy`); 31 (las: what builds it:
/// Limited Action Set edits, which the server does not take) (layout so far in
/// the fact file's `opcode.0x247.las`); 32 (build_switch: what builds it:
/// action set switching, which is not built) (layout so far in the fact file's
/// `opcode.0x247.build_switch`); 33 (datacube: what builds it: datacubes
/// (lore), which are not built; which addon handles its event is not searched)
/// (layout so far in the fact file's `opcode.0x247.datacube`); 35
/// (healing_absorption: what builds it: a heal-absorb effect, none is built)
/// (layout so far in the fact file's `opcode.0x247.healing_absorption`).
pub type CombatLogEntry {
  /// Kind 1, read by `combat_log_cc_state`. The fact file's
  /// `opcode.0x247.cc_state` names the kind.
  CcState(CombatLogCcState)
  /// Kind 2, read by `combat_log_cc_state_break`. The fact file's
  /// `opcode.0x247.cc_state` names the kind.
  CcStateBreak(CombatLogCcStateBreak)
  /// Kind 14, read by `combat_log_modify_interrupt_armor`. The fact file's
  /// `opcode.0x247.modify_interrupt_armor` names the kind.
  ModifyInterruptArmor(CombatLogModifyInterruptArmor)
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
    ModifyInterruptArmor(variant) ->
      combat_log_modify_interrupt_armor.write(writer, variant)
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
    14 ->
      reader
      |> combat_log_modify_interrupt_armor.read
      |> result.map(pair.map_first(_, ModifyInterruptArmor))
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
