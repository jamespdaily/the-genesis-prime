//// The crowd-control messages against bytes packed by hand from the layouts in the
//// fact file: `opcode.0x87f` (unit 32 bits, state 5, instance id 32),
//// `opcode.0x880` (unit 32, state 5, cast id 32, instance id 32, one bit) and
//// `opcode.0x247.cc_state` (type 1: state 5, removed 1, Interrupt Armor hit 32,
//// result 4, diminishing returns id 14, then the cast data: caster 32, target 32,
//// Spell4 18, combat result 4; type 2: unit 32, state 5), each after the 6-bit type
//// of `opcode.0x247`. Each vector was packed by a script that follows the bit
//// stream's rule, the least significant bit of the first byte first, field by field
//// with the widths the facts give, and shares no code with the codec. The states are
//// `Unit.CodeEnumCCState` (0 Stun, 8 Knockdown); the unit 20, the instance id 28673
//// (unit 7 x 4096 + 1) and Kick's Spell4 58591 are the values named beside each
//// vector. The bytes decode to the values, the values encode back to them, and every
//// shorter run of the bytes ends inside a field.

import genesis_prime/message/combat_log.{CombatLog}
import genesis_prime/message/combat_log_cc_state.{CombatLogCcState}
import genesis_prime/message/combat_log_cc_state_break.{CombatLogCcStateBreak}
import genesis_prime/message/combat_log_entry
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_result
import genesis_prime/message/crowd_control_state.{Knockdown, Stun}
import genesis_prime/message/unit_cc_state_applied.{UnitCcStateApplied}
import genesis_prime/message/unit_cc_state_ended.{UnitCcStateEnded}
import message_support
import owned_test

pub fn a_unit_holds_a_state_is_the_unit_the_state_and_the_instance_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x87f: unit 20 in 32 bits, Knockdown 8 in 5, instance id 28673 in 32",
    body: message_support.hex("14 00 00 00 28 00 0e 00 00"),
    value: UnitCcStateApplied(
      unit_id: 20,
      state: Knockdown,
      instance_id: 28_673,
    ),
    encode: unit_cc_state_applied.encode,
    decode: unit_cc_state_applied.decode,
  )
}

pub fn a_state_ends_is_the_unit_the_state_the_cast_the_instance_id_and_a_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x880: unit 20, Stun 0 in 5 bits, cast id 2147500000, instance id 28673, last bit 0",
    body: message_support.hex("14 00 00 00 00 fc 07 00 30 00 0e 00 00"),
    value: UnitCcStateEnded(
      unit_id: 20,
      state: Stun,
      cast_id: 2_147_500_000,
      instance_id: 28_673,
      keeps_flag_4_entries: 0,
    ),
    encode: unit_cc_state_ended.encode,
    decode: unit_cc_state_ended.decode,
  )
}

pub fn the_combat_log_carries_a_state_set_removed_or_broken_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x247.cc_state type 1: Knockdown set (removed 0), no armor hit, result Ok, no category, caster 7, target 20, Spell4 58591, combat result Hit",
    body: message_support.hex(
      "01 02 00 00 00 00 00 c0 01 00 00 00 05 00 00 c0 37 39 02",
    ),
    value: CombatLog(
      entry: combat_log_entry.CcState(CombatLogCcState(
        state: Knockdown,
        removed: 0,
        interrupt_armor_hit: 0,
        result: crowd_control_result.Ok,
        diminishing_returns_id: 0,
        caster_unit_id: 7,
        target_unit_id: 20,
        spell4_id: 58_591,
        combat_result: combat_result.Hit,
      )),
    ),
    encode: combat_log.encode,
    decode: combat_log.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x247.cc_state type 1: Stun removed (removed 1)",
    body: message_support.hex(
      "01 08 00 00 00 00 00 c0 01 00 00 00 05 00 00 c0 37 39 02",
    ),
    value: CombatLog(
      entry: combat_log_entry.CcState(CombatLogCcState(
        state: Stun,
        removed: 1,
        interrupt_armor_hit: 0,
        result: crowd_control_result.Ok,
        diminishing_returns_id: 0,
        caster_unit_id: 7,
        target_unit_id: 20,
        spell4_id: 58_591,
        combat_result: combat_result.Hit,
      )),
    ),
    encode: combat_log.encode,
    decode: combat_log.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x247.cc_state type 2: unit 20 in 32 bits, Knockdown in 5",
    body: message_support.hex("02 05 00 00 00 02"),
    value: CombatLog(
      entry: combat_log_entry.CcStateBreak(CombatLogCcStateBreak(
        unit_id: 20,
        state: Knockdown,
      )),
    ),
    encode: combat_log.encode,
    decode: combat_log.decode,
  )
}
