//// The player striker the strike rule's tests and the cast rule's tests that compose it
//// begin a round with.

import genesis_prime/game/area.{Point, Pose}
import genesis_prime/game/damage
import genesis_prime/game/shown.{Exile}
import genesis_prime/game/spell_area.{DamageEffect}
import genesis_prime/game/spell_plan.{AimsAtArea}
import genesis_prime/game/spend
import genesis_prime/game/strike.{type Attacker, Attacker}
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{Spell4EffectsId}
import map_support
import place_support
import properties_support

/// Player 7 on connection 2, a level 1 Exile at the origin of world 3460.
pub fn attacker() -> Attacker {
  Attacker(
    unit_id: 7,
    connection: ConnectionId(2),
    pose: Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    move_seq: 1,
    stay: map_support.stay(count: 1),
    hit_radius: place_support.player_hit_radius,
    faction: Exile,
    stats: damage.Attacker(level: 1, assault_rating: 0.0, support_rating: 0.0),
    properties: properties_support.fresh(level: 1),
  )
}

/// A damage effect on every phase that aims at the area, which makes a round wait for the
/// answers of the units it strikes.
pub fn damage_effect() -> spell_area.DamageEffect {
  DamageEffect(
    effect_id: Spell4EffectsId(1),
    damage_type: 1,
    delay_ms: 166,
    phase_flags: -1,
    aim: AimsAtArea,
    formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: []),
    threat_multiplier: 1.0,
    tag: spend.always,
  )
}
