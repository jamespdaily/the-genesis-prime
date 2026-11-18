//// What the level-up fanfare's tests share: the Level Up spell's tiers as the client's rows
//// hold them, written out by hand so no test takes its expected value from the code under
//// test, and the bytes of the client's 0x07A5.

import gleam/list

/// One tier of the Level Up spell, Spell4Base 53378, as a level's fanfare.
pub type Tier {
  Tier(level: Int, spell4_id: Int, effect_id: Int)
}

/// The tiers the tests name, from `table_rows -- Spell4 spell4BaseIdBaseSpell=53378` and
/// `-- Spell4Effects spellId=<id>` (`Spell4.tierIndex.level_up`): the Spell4 ids are not
/// consecutive (tier 1 is 77398, tier 2 is 77407, tiers 3 to 49 are 77409 to 77455), and the
/// level is the tier's tierIndex plus 1.
pub const tiers = [
  Tier(level: 2, spell4_id: 77_398, effect_id: 202_311),
  Tier(level: 3, spell4_id: 77_407, effect_id: 202_340),
  Tier(level: 4, spell4_id: 77_409, effect_id: 202_345),
  Tier(level: 5, spell4_id: 77_410, effect_id: 202_346),
  Tier(level: 12, spell4_id: 77_417, effect_id: 202_353),
  Tier(level: 22, spell4_id: 77_427, effect_id: 202_364),
  Tier(level: 50, spell4_id: 77_455, effect_id: 202_395),
]

/// The tier of a level among `tiers`.
pub fn tier(level level: Int) -> Tier {
  let assert Ok(found) = list.find(tiers, fn(tier) { tier.level == level })
    as "the table names the level"
  found
}

/// The body of the client's 0x07A5 for a level: one 32-bit value, low byte first
/// (`opcode.0x7a5`, writer `WriteUint32Body 0x14007d010`).
pub fn replay_body(level level: Int) -> BitArray {
  <<level:32-little>>
}
