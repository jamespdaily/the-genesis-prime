//// The records a 0x7f4 go and a 0x262 cast entry share: a unit's target info and each
//// effect info on it. The go (`game/cast/frame`), a creature's applied effects and a
//// unit's cast list (`game/unit_casts`) build them here, so the three write the same
//// bytes for the same fields. This module imports only message records, so each of
//// them can import it.

import genesis_prime/message/combat_result.{type CombatResult}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{
  type SpellEffectInfo, SpellEffectInfo,
}
import genesis_prime/message/spell_effect_result.{type SpellEffectResult}
import genesis_prime/message/spell_target_info.{
  type SpellTargetInfo, SpellTargetInfo,
}

/// One unit's target info: its place in the list, target flags 0
/// (`opcode.0x7f4.target_info`), the cast's count on it and the combat result.
pub fn target(
  index index: Int,
  unit_id unit_id: Int,
  instance_count instance_count: Int,
  combat_result combat_result: CombatResult,
  effects effects: List(SpellEffectInfo),
) -> SpellTargetInfo {
  SpellTargetInfo(
    unit_id:,
    index:,
    flags: 0,
    instance_count:,
    combat_result:,
    effects:,
  )
}

/// One effect info: the Spell4Effects id, its instance id, the delay still to run
/// and the lifetime (`opcode.0x7f4.effect_delay`, `opcode.0x7f4.effect_time`).
pub fn effect(
  effect_id effect_id: Int,
  instance_id instance_id: Int,
  delay_ms delay_ms: Int,
  lifetime_ms lifetime_ms: Int,
  result result: SpellEffectResult,
) -> SpellEffectInfo {
  SpellEffectInfo(
    spell4_effects_id: effect_id,
    instance_id:,
    delay_ms:,
    lifetime_ms:,
    result:,
  )
}

/// The result of an effect that tells no value: the bit whose meaning the client's
/// reader does not use.
pub fn bit() -> SpellEffectResult {
  spell_effect_result.Bit(SpellEffectBit(unread_2: 0))
}
