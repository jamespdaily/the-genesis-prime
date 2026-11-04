//// What a strike does to a unit's health: the one rule of a hit. It runs in
//// the process that owns the struck unit (genesis_prime/world_map/creature_life),
//// on the caster's offence and the caster's rolls, so the health, the overkill and
//// the killed bit stay exact when two strikes cross.
////
//// ```
//// caster (genesis_prime/game/strike)                  struck unit's owner
////   blows from the effects' formulas (genesis_prime/game/damage)
////   crit chance and severity (genesis_prime/game/rating)
////   rolls from the connection's seed ───────────────▶ apply(health, offence, defence, rolls)
////                                                      deflect roll < deflect chance ─▶ Deflected
////                                                      else each blow lands: crit roll < crit chance ─▶ x severity
////                                                      health' = max(0, health - damage); killed at 0
//// ```
////
//// - **A deflect** lands when the deflect roll is below the target's deflect chance
////   (`0x140463340`): the whole strike is missed, and the client shows it from a
////   0x7fb, not a description (`opcode.0x7fb`).
//// - **A critical hit** lands when the crit roll is below the caster's crit chance
////   (`0x140463700`), at the caster's crit severity (`0x140463e80`, 1.5 for a
////   Novice); a landed blow is a Hit (result 2) or a Critical (result 1)
////   (`GameLib.CodeEnumCombatResult`).
//// - **The damage** of a blow is a whole number, rounded half away from zero
////   (the server's choice: the client rounds only the stat part,
////   `0x140566d40`), times the severity for a critical hit, rounded again.
//// - **Health** stays in [0, max]; the killed bit is set exactly when the blow takes
////   it to 0; the overkill is the damage beyond the health before the blow.
//// - **Mitigation** is not applied: the Virtual Battle Beast has none
////   (`Creature2.73464.mitigation`), and a creature with armor is struck as if it
////   had none, which is a gap, not a client fact.
//// - **One roll pair for each strike.** A strike with several blows rolls once, so
////   a deflect misses all and a critical hit multiplies all.

import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription,
}

/// One damage effect as the caster worked it out: the Spell4Effects row, the
/// damage type, the damage before any critical hit as a whole number, and the
/// effect's delay (the client applies the description after it).
pub type Blow {
  Blow(spell4_effects_id: Int, damage_type: Int, damage: Int, delay_ms: Int)
}

/// What the caster brings to a strike: its blows and its critical hit chance
/// and severity, as fractions (1.5 is a half again).
pub type Offence {
  Offence(blows: List(Blow), crit_chance: Float, crit_severity: Float)
}

/// What the target brings: its chance to deflect, as a fraction.
pub type Defence {
  Defence(deflect_chance: Float)
}

/// The caster's two rolls for a strike, each in [0, 1): the critical hit roll
/// and the deflect roll, drawn from the caster's seed so a recording replays them.
pub type Rolls {
  Rolls(crit: Float, deflect: Float)
}

/// One landed blow as the go's target info carries it: the effect's row and
/// delay, and the damage description the client makes the number, the hit
/// reaction and the combat log line from.
pub type Description {
  Description(
    spell4_effects_id: Int,
    delay_ms: Int,
    damage: SpellDamageDescription,
  )
}

/// What a strike did to a unit with `health` before it.
pub type Outcome {
  /// The blows landed: a description for each, the health after them and
  /// whether the last took it to 0.
  Landed(descriptions: List(Description), health: Int, killed: Bool)
  /// The target deflected the whole strike.
  Deflected
}

/// The rolls the seed's 8 bytes make: two fractions of 4 bytes each, so each
/// roll is a multiple of 2^-32 below 1. `Error(Nil)` for any other length.
pub fn rolls_of(bytes bytes: BitArray) -> Result(Rolls, Nil) {
  unbuilt(inputs: bytes)
}

/// The hit rule: what `offence` does to a unit with `health` and `defence`, on
/// `rolls`. A health of 0 is a dead unit, which no strike reaches
/// (genesis_prime/world_map/creature_life refuses it first).
pub fn apply(
  health health: Int,
  offence offence: Offence,
  defence defence: Defence,
  rolls rolls: Rolls,
) -> Outcome {
  unbuilt(inputs: #(health, offence, defence, rolls))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
