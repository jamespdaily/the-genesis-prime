//// The player striker the strike rule's tests and the cast rule's tests that compose it
//// begin a round with.

import attacker_support
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/player_address
import genesis_prime/game/shown.{Exile, ShownCreature}
import genesis_prime/game/strike.{type Attacker, Attacker}
import genesis_prime/game/strike_tell
import genesis_prime/shared/area.{type Pose, Point, Pose}
import genesis_prime/shared/creature_path
import genesis_prime/shared/damage
import genesis_prime/shared/effect_kind
import genesis_prime/shared/spell_area.{DamageEffect}
import genesis_prime/shared/spell_plan.{AimsAtArea}
import genesis_prime/shared/spend
import genesis_prime/step.{type LogLevel, type TimerId, ConnectionId}
import genesis_prime/table/id.{Creature2Id, Spell4EffectsId}
import genesis_prime/world_map/creature_life.{type Attackable, Hostile}
import genesis_prime/world_map/spawn_id.{SpawnId}
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
    spawn_id: SpawnId(1),
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

// ---- reading what a strike gave ----

/// What one effect of a strike is.
pub type Kind {
  CreatureTold
  PlayerTold
  TimerStarted
  TimerCancelled
  RoundClosed
  TickClosed
  NewsReleased
  LineLogged
}

/// The kind of an effect: the one match over every variant of `strike.Effect` the tests
/// read, so a variant added to it is added here and nowhere else.
pub fn kind_of(effect effect: strike.Effect) -> Kind {
  case effect {
    strike.TellStrike(..) -> CreatureTold
    strike.TellPlayerStrike(..) -> PlayerTold
    strike.StartTimer(..) -> TimerStarted
    strike.CancelTimer(..) -> TimerCancelled
    strike.Went(..) -> RoundClosed
    strike.Ticked(..) -> TickClosed
    strike.Released(..) -> NewsReleased
    strike.Log(..) -> LineLogged
  }
}

/// The effects of one of these kinds, in order.
pub fn only(
  effects effects: List(strike.Effect),
  kinds kinds: List(Kind),
) -> List(strike.Effect) {
  list.filter(effects, fn(effect) { list.contains(kinds, kind_of(effect:)) })
}

/// The creature strikes told, each as its unit, its life and the tell.
pub fn creatures_told(
  effects effects: List(strike.Effect),
) -> List(#(Int, Int, strike_tell.Tell)) {
  list.map(only(effects:, kinds: [CreatureTold]), fn(effect) {
    let assert strike.TellStrike(unit_id:, life:, tell:) = effect
      as "only the creature strikes were kept"
    #(unit_id, life, tell)
  })
}

/// The heal strikes told to players, each as the player's address and the tell.
pub fn players_told(
  effects effects: List(strike.Effect),
) -> List(#(player_address.PlayerAddress, strike_tell.PlayerStrike)) {
  list.map(only(effects:, kinds: [PlayerTold]), fn(effect) {
    let assert strike.TellPlayerStrike(address:, strike:) = effect
      as "only the player strikes were kept"
    #(address, strike)
  })
}

/// The timers started, each as its id and its delay.
pub fn timers_started(
  effects effects: List(strike.Effect),
) -> List(#(TimerId, Int)) {
  list.map(only(effects:, kinds: [TimerStarted]), fn(effect) {
    let assert strike.StartTimer(timer:, after_ms:) = effect
      as "only the started timers were kept"
    #(timer, after_ms)
  })
}

/// The ids of the timers cancelled.
pub fn timers_cancelled(effects effects: List(strike.Effect)) -> List(TimerId) {
  list.map(only(effects:, kinds: [TimerCancelled]), fn(effect) {
    let assert strike.CancelTimer(timer:) = effect
      as "only the cancelled timers were kept"
    timer
  })
}

/// The rounds that closed with a go, each as the go asked, the units it struck and the
/// gates they passed.
pub fn rounds_closed(
  effects effects: List(strike.Effect),
) -> List(
  #(cast_state.GoAsked, List(cast_state.Struck), dict.Dict(Int, List(Int))),
) {
  list.map(only(effects:, kinds: [RoundClosed]), fn(effect) {
    let assert strike.Went(asked:, struck:, gates_passed:) = effect
      as "only the closed rounds were kept"
    #(asked, struck, gates_passed)
  })
}

/// The rounds that closed with a tick, each as the tick asked and the unit it struck.
pub fn ticks_closed(
  effects effects: List(strike.Effect),
) -> List(#(cast_state.TickAsked, Option(cast_state.Struck))) {
  list.map(only(effects:, kinds: [TickClosed]), fn(effect) {
    let assert strike.Ticked(asked:, struck:) = effect
      as "only the closed ticks were kept"
    #(asked, struck)
  })
}

/// The lines logged, each as its level and text.
pub fn lines_logged(
  effects effects: List(strike.Effect),
) -> List(#(LogLevel, String)) {
  list.map(only(effects:, kinds: [LineLogged]), fn(effect) {
    let assert strike.Log(level:, text:) = effect as "only the lines were kept"
    #(level, text)
  })
}

/// The timers the effects start or cancel.
pub fn timers(effects effects: List(strike.Effect)) -> List(strike.Effect) {
  only(effects:, kinds: [TimerStarted, TimerCancelled])
}
