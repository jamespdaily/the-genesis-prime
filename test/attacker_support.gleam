//// The level-1 Novice the formula tests read: the one place its numbers are written.

import genesis_prime/message/float32
import genesis_prime/shared/damage.{
  type Attacker, type OnCaster, type Vitals, Attacker, OnCaster, Vitals,
}
import properties_support

/// A level-1 player with no gear: every property at its UnitProperty2 default, as the
/// formula reads them (`damage.attacker_of`), and the passed-in value at level 1, 5.3 as a
/// 32-bit float (the family-33 curve, `0x14041f1b0`).
pub fn fresh() -> Attacker {
  damage.attacker_of(
    properties: properties_support.fresh(level: 1),
    level: 1,
    passed_in: float32.rounded(5.3),
  )
}

/// A level-1 Novice's gear gives Assault Rating 203.0625 and Support Rating 55.6875 for
/// every class (`player.level1_gear_properties`, `loadout_test`).
pub fn novice() -> Attacker {
  Attacker(..fresh(), assault_rating: 203.0625, support_rating: 55.6875)
}

/// A level-1 Novice's health and shield, full (736 and 450).
pub fn novice_vitals() -> Vitals {
  Vitals(health: 736, max_health: 736, shield: 450, max_shield: 450)
}

/// The same Novice as the caster and target of its own effect, at full health and shield.
pub fn novice_on_itself() -> OnCaster {
  OnCaster(attacker: novice(), vitals: novice_vitals())
}
