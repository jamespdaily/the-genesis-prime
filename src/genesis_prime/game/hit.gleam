//// What a strike does to a unit's health: the one rule of a hit. It runs in
//// the process that owns the struck unit (genesis_prime/world_map/creature_life),
//// on the caster's offence and the caster's rolls, so the health, the overkill and
//// the killed bit stay exact when two strikes cross.
////
//// ```
//// caster (genesis_prime/game/strike)                  struck unit's owner
////   blows from the effects' formulas (genesis_prime/game/damage)
////   crit and strikethrough (genesis_prime/game/rating)
////   rolls from the connection's seed ───────────────▶ apply(health, offence, defence, rolls)
////                                                      deflect roll < deflect chance - strikethrough ─▶ Deflected
////                                                      each blow: crit roll < crit chance - crit deflect ─▶ x severity
////                                                                 glance roll < glance chance ─▶ less the glance amount
////                                                                 x (1 - mitigation of its damage type)
////                                                      health' = max(0, health - damage); killed at 0
//// ```
////
//// - **The order** is deflect, base damage, crit, glance, mitigation (the step's
////   design, 274 section 4: the client has each percentage, not their combination, so
////   the order and what each multiplies are the server's choice).
//// - **A deflect** lands when the deflect roll is below the target's deflect chance
////   less the attacker's strikethrough, never below 0 (`0x140463340`, `0x140462ef0`):
////   the whole strike is missed, and the client shows it from a 0x7fb, not a
////   description (`opcode.0x7fb`).
//// - **A critical hit** lands when the crit roll is below the caster's crit chance
////   less the target's critical deflect, never below 0 (`0x140463700`,
////   `0x140463ac0`), at the caster's crit severity (`0x140463e80`, 1.5 for a Novice);
////   a landed blow is a Hit (result 2) or a Critical (result 1)
////   (`GameLib.CodeEnumCombatResult`).
//// - **A glance** lands when the glance roll is below the target's glance chance
////   (`0x140461a30`) and takes the target's glance amount off the damage
////   (`0x1404615f0`); the amount taken is the description's glance value.
//// - **Mitigation** takes the target's percentage for the blow's damage type off the
////   damage after the crit and the glance: the physical percentage is from the target's
////   Armor and ResistPhysical (`0x140464240`, `0x14064d9b0`), the tech and magic ones are
////   by the same formula from their twin properties, which the client's bodies were not
////   read for (a gap; the Virtual Battle Beast has none of the three,
////   `Creature2.73464.mitigation`). That it multiplies the damage is the server's
////   choice (`Creature2.73464.mitigation`). The damage absorbed is the amount taken.
//// - **The damage** of a blow is a whole number, rounded half away from zero (the
////   server's choice: the client rounds only the stat part, `0x140566d40`), and each
////   step rounds again.
//// - **Health** stays in [0, max]; the killed bit is set exactly when the blow takes
////   it to 0; the overkill is the damage beyond the health before the blow.
//// - **One roll triple for each strike.** A strike with several blows rolls once, so
////   a deflect misses all, a critical hit multiplies all and a glance reduces all.

import genesis_prime/message/combat_result.{Critical, Hit}
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import gleam/float
import gleam/int
import gleam/list

/// One damage effect as the caster worked it out: the Spell4Effects row, the
/// damage type, the damage before any critical hit as a whole number, and the
/// effect's delay (the client applies the description after it).
pub type Blow {
  Blow(spell4_effects_id: Int, damage_type: Int, damage: Int, delay_ms: Int)
}

/// What the caster brings to a strike: its blows, its critical hit chance and
/// severity and its strikethrough, as fractions (1.5 is a half again).
pub type Offence {
  Offence(
    blows: List(Blow),
    crit_chance: Float,
    crit_severity: Float,
    strikethrough: Float,
  )
}

/// What the target brings, as fractions: its chances to deflect, to deflect a
/// critical hit and to glance, the share a glance takes off, and its mitigation of
/// each damage type.
pub type Defence {
  Defence(
    deflect_chance: Float,
    crit_deflect_chance: Float,
    glance_chance: Float,
    glance_amount: Float,
    physical_mitigation: Float,
    tech_mitigation: Float,
    magic_mitigation: Float,
  )
}

/// A defence that stops nothing: every chance and mitigation 0.
pub const unprotected =
  Defence(
    deflect_chance: 0.0,
    crit_deflect_chance: 0.0,
    glance_chance: 0.0,
    glance_amount: 0.0,
    physical_mitigation: 0.0,
    tech_mitigation: 0.0,
    magic_mitigation: 0.0,
  )

/// The caster's rolls for a strike, each in [0, 1): the critical hit roll, the
/// deflect roll and the glance roll, drawn from the caster's seed so a recording
/// replays them.
pub type Rolls {
  Rolls(crit: Float, deflect: Float, glance: Float)
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
  /// whether a blow took it to 0.
  Landed(descriptions: List(Description), health: Int, killed: Bool)
  /// The target deflected the whole strike.
  Deflected
}

/// The bytes of the rolls of one strike: 4 for each roll.
pub const roll_bytes = 12

/// The rolls the seed's 12 bytes make: three fractions of 4 bytes each, so each
/// roll is a multiple of 2^-32 below 1. `Error(Nil)` for any other length.
pub fn rolls_of(bytes bytes: BitArray) -> Result(Rolls, Nil) {
  case bytes {
    <<crit:size(32), deflect:size(32), glance:size(32)>> ->
      Ok(Rolls(
        crit: fraction(crit),
        deflect: fraction(deflect),
        glance: fraction(glance),
      ))
    _ -> Error(Nil)
  }
}

fn fraction(number: Int) -> Float {
  int.to_float(number) /. 4_294_967_296.0
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
  let deflect_chance =
    float.max(0.0, defence.deflect_chance -. offence.strikethrough)
  case rolls.deflect <. deflect_chance {
    True -> Deflected
    False -> {
      let crit_chance =
        float.max(0.0, offence.crit_chance -. defence.crit_deflect_chance)
      let critical = rolls.crit <. crit_chance
      let glancing = rolls.glance <. defence.glance_chance
      let #(descriptions, left, killed) =
        list.fold(offence.blows, #([], health, False), fn(so_far, blow) {
          let #(done, left, killed) = so_far
          let raw = case critical {
            True ->
              float.round(int.to_float(blow.damage) *. offence.crit_severity)
            False -> blow.damage
          }
          let glanced = case glancing {
            True -> float.round(int.to_float(raw) *. defence.glance_amount)
            False -> 0
          }
          let after_glance = raw - glanced
          let taken =
            float.round(
              int.to_float(after_glance)
              *. { 1.0 -. mitigation_of(defence:, blow:) },
            )
          let mitigated = after_glance - taken
          let overkill = int.max(0, taken - left)
          let kills = left > 0 && taken >= left
          let description =
            Description(
              spell4_effects_id: blow.spell4_effects_id,
              delay_ms: blow.delay_ms,
              damage: described(
                blow:,
                raw:,
                mitigated:,
                taken:,
                overkill:,
                glanced:,
                kills:,
                critical:,
              ),
            )
          #([description, ..done], int.max(0, left - taken), killed || kills)
        })
      Landed(descriptions: list.reverse(descriptions), health: left, killed:)
    }
  }
}

fn mitigation_of(defence defence: Defence, blow blow: Blow) -> Float {
  case damage_type.from_value(blow.damage_type) {
    damage_type.Physical -> defence.physical_mitigation
    damage_type.Tech -> defence.tech_mitigation
    damage_type.Magic -> defence.magic_mitigation
    damage_type.Heal
    | damage_type.HealShields
    | damage_type.Fall
    | damage_type.Suffocate
    | damage_type.Other(..) -> 0.0
  }
}

fn described(
  blow blow: Blow,
  raw raw: Int,
  mitigated mitigated: Int,
  taken taken: Int,
  overkill overkill: Int,
  glanced glanced: Int,
  kills kills: Bool,
  critical critical: Bool,
) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: raw,
    scaled_raw_damage: raw,
    absorbed: mitigated,
    shield_absorbed: 0,
    health_damage_with_overkill: taken,
    overkill:,
    glance: glanced,
    killed: case kills {
      True -> 1
      False -> 0
    },
    combat_result: case critical {
      True -> Critical
      False -> Hit
    },
    damage_type: damage_type.from_value(blow.damage_type),
    hits: [],
  )
}
