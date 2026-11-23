//// The player striker the strike rule's tests and the cast rule's tests that compose it
//// begin a round with.

import attacker_support
import genesis_prime/game/area.{type Pose, Point, Pose}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/shown.{Exile, ShownCreature}
import genesis_prime/game/spell_area.{DamageEffect}
import genesis_prime/game/spell_plan.{AimsAtArea}
import genesis_prime/game/spend
import genesis_prime/game/strike.{type Attacker, Attacker}
import genesis_prime/game/strike_tell
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{Creature2Id, Spell4EffectsId}
import genesis_prime/world_map/creature_life.{type Attackable, Hostile}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict
import gleam/list
import gleam/option.{type Option}
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
    stats: attacker_support.fresh(),
    vitals: attacker_support.novice_vitals(),
    properties: properties_support.fresh(level: 1),
    players_in_sight: dict.new(),
  )
}

/// The heal strike of the caster's connection `from` on the unit `unit_id`, for the cast
/// `cast_id`'s first phase: the caster's stay `stay` (which the answer is told for), the
/// caster's HealingMultiplierOutgoing `outgoing` and the heal rows `heals` in order, each
/// healing the vital by the amount before any multiplier. The row `index` is
/// Spell4Effects 62019 + `index`, which the answer echoes.
pub fn heal_strike(
  from from: step.ConnectionId,
  stay stay: Stay,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  outgoing outgoing: Float,
  heals heals: List(#(effect_kind.Vital, Int)),
) -> strike_tell.PlayerStrike {
  strike_tell.PlayerStrike(
    key: strike_tell.Key(
      cast_id:,
      occasion: strike_tell.AtGo(phase: 0),
      unit_id:,
    ),
    from:,
    stay:,
    outgoing:,
    heals: list.index_map(heals, fn(heal, index) {
      strike_tell.HealTell(
        effect_id: Spell4EffectsId(62_019 + index),
        vital: heal.0,
        amount: heal.1,
      )
    }),
  )
}

/// The pose a go's cast started at when a test is not about the start: the attacker's own.
pub fn start_pose() -> Pose {
  attacker().pose
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
    condition: spell_plan.Always,
    tag: spend.always,
  )
}

/// A gate that lets every row start for every unit and takes no roll: the rows of the
/// tests that are behind no apply prerequisite.
pub fn passes_all() -> cast_state.StrikeGate {
  fn(_, _, _, rolls) { #(cast_state.Starts, rolls) }
}

/// A standing creature of Creature2 73464 at `x`, `z` in world 3460, a foe of nobody or
/// both factions by `attackable`.
pub fn creature_at(
  x x: Float,
  z z: Float,
  alive alive: Bool,
  attackable attackable: Attackable,
) -> shown.Shown {
  creature_facing(x:, z:, alive:, attackable:, faced_yaw: option.None)
}

/// The same creature held to the yaw `faced_yaw` by its owner's news, or facing as its place
/// does with none.
pub fn creature_facing(
  x x: Float,
  z z: Float,
  alive alive: Bool,
  attackable attackable: Attackable,
  faced_yaw faced_yaw: Option(Float),
) -> shown.Shown {
  ShownCreature(
    creature_id: Creature2Id(73_464),
    faction_id: 0,
    checklist_index: 0,
    path: creature_path.Standing(at: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x:,
      y: 0.0,
      z:,
    )),
    life: 4,
    alive:,
    hit_radius: 3.0,
    attackable:,
    hostile_to: Hostile(exile: False, dominion: False),
    in_combat: False,
    held: [],
    unit_states: [],
    face: option.None,
    faced_yaw:,
    fights: True,
  )
}
