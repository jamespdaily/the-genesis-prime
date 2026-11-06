//// What a CCStateSet effect (`Spell4Effects.effectType.4`) is to the server before
//// any creature holds it: the columns of its row and the instance id its go gives
//// it. The caster's strike carries the row's state to the creature that owns the
//// struck unit (genesis_prime/game/strike_tell `ControlTell`), the creature holds it
//// and ends it (genesis_prime/world_map/creature_control), and the cast rule lists
//// it in the go (genesis_prime/game/cast).
////
//// - **The state** is the row's dataBits00 (`Unit.CodeEnumCCState`): the plan reads
////   Stun (0) and Knockdown (8) and fails the load for any other state
////   (genesis_prime/game/spell_plan).
//// - **The instance id** names one effect on one unit. The client finds the effect a
////   0x87f waits for by instance id alone among every effect held on the unit, from
////   any caster, and 0 matches the first effect found (`cc_state.instance_id`), so an
////   id is non-zero and no two effects on a unit share one. It is made from the
////   caster's unit id and the caster's own count of the states it told (`instance_id`).

import genesis_prime/message/crowd_control_state.{type CrowdControlState}

/// The columns of a CCStateSet row that decide how long and how a state lands:
/// its state (dataBits00), delayTime and durationTime in milliseconds, and the
/// Interrupt Armor it removes (dataBits03). The client's own lifetime for the effect
/// scales durationTime by the target's CC resilience, which is 0 for every creature
/// (`cc_state.duration_on_creature`), so a creature holds the state for durationTime.
pub type Row {
  Row(
    state: CrowdControlState,
    delay_ms: Int,
    duration_ms: Int,
    armor_removed: Int,
  )
}

/// How many numbers of one caster the encoding holds: 1 to 4095 in the low 12 bits.
const numbers_per_caster = 4095

/// The instance id of the `count`th state the unit `caster_unit_id` told: its unit id
/// times 4096 plus `count` wrapped into 1 to 4095.
///
/// - Within 32 bits: a unit id is below 2^20, the bound `cast.cast_id` already holds
///   (its 2^31 + unit id x 2^11 stays in 32 bits), and 4095 + 4096 x (2^20 - 1) is
///   2^32 - 1.
/// - Non-zero: the low part is 1 to 4095, and unit ids start at 1, so an id is also
///   4096 or more, which no damage or Fluff instance id is (those number from 1 for
///   each unit in one go, `cast.target_info`).
/// - Unique on a unit across casters: two casters differ in the quotient by 4096,
///   since the low part is below 4096.
/// - Unique for one caster: two of its ids on one unit are equal only when its counts
///   are 4095 apart, which needs 4095 more states told while the first is still held
///   (a state lasts seconds).
pub fn instance_id(
  caster_unit_id caster_unit_id: Int,
  count count: Int,
) -> Int {
  caster_unit_id * 4096 + { count - 1 } % numbers_per_caster + 1
}
