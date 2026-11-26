//// News of one unit from its owner to the connections of the players who see it: what a
//// player's connection or a creature's process tells, which each viewer writes as the
//// message the client creates, moves and removes a unit with
//// (genesis_prime/game/connection/viewers). It sits below the map
//// (genesis_prime/world_map/map) so that the map and the creature can name it.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/spell_effect_tick.{type SpellEffectTick}
import genesis_prime/message/spell_go.{type SpellGo}
import genesis_prime/message/spell_missed.{type SpellMissed}
import genesis_prime/message/spell_stack_removed.{type SpellStackRemoved}
import genesis_prime/message/spell_started.{type SpellStarted}
import genesis_prime/message/spell_targets_removed.{type SpellTargetsRemoved}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/world_map/creature_life.{type Attackable, type Hostile}
import genesis_prime/world_map/creature_path.{type Path}
import genesis_prime/world_map/creature_turn.{type Face}
import genesis_prime/world_map/creature_unit_type.{type CreatureUnitType}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/spawn_id.{type SpawnId}

/// News of one unit from its owner, a player's connection or a creature's
/// process, to the connection of a player who sees it: the owner's unit in the
/// run of the map both are in, and what happened to it. It travels for the
/// viewer's stay (`TellPeer`, `ForStay`), which names that run.
pub type PeerNews {
  PeerNews(unit_id: Int, news: News)
}

/// What a unit's owner tells the connections that see its unit, which they write
/// as the message the client creates, moves and removes a unit with.
pub type News {
  /// The unit as the client creates it, at the owner's current place and stamped
  /// from the map's clock: 0x262 (opcode.0x262), for the sight `generation` names:
  /// the viewer's moves of the unit are for that generation from now on
  /// (genesis_prime/game/move_stamp).
  Appeared(unit: UnitCreatePlayer, generation: Generation)
  /// A creature as the client creates it, at its spawn and stamped from the
  /// map's clock: 0x262 of type 0 (opcode.0x262.creature), or of type 13 when
  /// `unit_type` is a Turret (opcode.0x262.simple), at its current health
  /// (0 for a corpse). Sent by the creature's own process
  /// (genesis_prime/world_map/creature), which owns the unit, with what the viewer's
  /// strikes and requests need of it: its life, which its address needs, the hit
  /// radius of its display, whom it may be attacked by, which player factions it
  /// is Hostile to and whether it takes part in combat (`creature_life.Combat.fights`),
  /// which an area's candidates read, and the id of its spawn, which a quest objective
  /// remembers a use of it by (`quest_log.used`).
  CreatureAppeared(
    unit: UnitCreateCreature,
    unit_type: CreatureUnitType,
    spawn_id: SpawnId,
    life: Int,
    place: Place,
    hit_radius: Float,
    attackable: Attackable,
    hostile_to: Hostile,
    fights: Bool,
  )
  /// A player's unit left the viewer's sight, or its owner camped, at the end of the
  /// sight `generation` names: 0x355 (opcode.0x355), and the moves of that sight and
  /// the ones before it are late ones (genesis_prime/game/move_stamp).
  Departed(generation: Generation)
  /// A creature's unit is gone from the viewer's sight: 0x355 (opcode.0x355).
  Removed
  /// The unit started a cast: 0x7ff (opcode.0x7ff), written when the viewer's
  /// client shows the unit, and the cast is then one the viewer knows.
  CastStarted(start: SpellStarted)
  /// A cast of the unit goes off: 0x7f4 (opcode.0x7f4), written for a cast the
  /// viewer wrote the start of.
  CastWent(go: SpellGo)
  /// Some targets of a cast of the unit were missed: 0x7fb (opcode.0x7fb), written for
  /// a cast the viewer wrote the start of, after its 0x7f4.
  CastMissed(missed: SpellMissed)
  /// A periodic row of a cast of the unit ticks on a unit: 0x7f8 (opcode.0x7f8),
  /// written for a cast the viewer wrote the start of.
  CastTicked(tick: SpellEffectTick)
  /// A cast of the unit is taken off some units, which ends its effects there:
  /// 0x811 (opcode.0x811), written for a cast the viewer wrote the start of. With
  /// `destroyed`, the client destroys the cast with it (no target left and a cast
  /// method other than 1, 3, 8 and 10), so the viewer forgets it.
  CastTargetsRemoved(removed: SpellTargetsRemoved, destroyed: Bool)
  /// A cast of the unit loses one stack on a unit: 0x813 (opcode.0x813), written
  /// for a cast the viewer wrote the start of.
  CastStackRemoved(removed: SpellStackRemoved)
  /// A cast of the unit ends: 0x7fe (opcode.0x7fe), written for a cast the viewer
  /// wrote the start of, which the viewer then forgets.
  CastFinished(cast_id: Int)
  /// A cast of the unit is interrupted: 0x7f9 with the result `cast_result.SpellInterrupted`
  /// (11) and the unit, then the 0x7fe of `CastFinished` (opcode.0x7f9), written for a cast the
  /// viewer wrote the start of, which the viewer then forgets. A creature's charge that a crowd-control
  /// state broke is shown so (genesis_prime/world_map/creature_fight).
  CastInterrupted(cast_id: Int)
  /// The unit's health after a landed hit, from the creature that owns it: 0x937
  /// (opcode.0x937), written when the viewer's client shows the unit, whatever
  /// the viewer's own casts.
  Health(health: Int, dead: Bool)
  /// The unit died: 0x88c with the dead bit (opcode.0x88c), written when the
  /// viewer's client shows the unit.
  Died
  /// The unit came back from death: 0x88c with the dead bit clear
  /// (opcode.0x88c), written when the viewer's client shows the unit.
  CameBack
  /// A player's death for the combat log: 0x247 of type 22 (opcode.0x247.death),
  /// written when the viewer's client shows the unit. The client logs it only
  /// for a player or a ghost, so a creature never sends it.
  DeathLogged
  /// A player's coming back for the combat log: 0x247 of type 23
  /// (opcode.0x247.death), written when the viewer's client shows the unit.
  CameBackLogged
  /// A creature runs `path`: 0x638 of kind 0, the map's time it starts at, and
  /// kind 4, the path (`movement_command.kind_4`), written when the viewer's
  /// client shows the unit; the viewer keeps the path for its picture
  /// (genesis_prime/game/shown).
  CreatureMoved(path: Path)
  /// A creature that stands at `place` from monotonic time `at_ms`, though the
  /// viewer's client may still run a path it was sent: 0x638 of kind 0, the map's
  /// time, and kind 2 at the place with its blend bit clear, which places the unit
  /// at once (`0x1407138f0`, `0x140714120`); the viewer
  /// keeps it standing there for its picture.
  CreaturePlaced(place: Place, at_ms: Int)
  /// A creature's rotation changes to `face` from monotonic time `at_ms`: 0x638 of kind 0, the
  /// map's time, and kind 18 (a unit), kind 19 (a point) or kind 14 (a fixed facing), written
  /// when the viewer's client shows the unit; the viewer keeps the face for its picture
  /// (genesis_prime/world_map/creature_turn, genesis_prime/game/shown). It moves nothing: a
  /// path and a place leave the rotation as it was.
  CreatureFaces(face: Face, at_ms: Int)
  /// The unit targets `target_unit_id` with `threat`: 0x908 (opcode.0x908).
  Targeting(target_unit_id: Int, threat: Int)
  /// The unit holds `threat` toward `other_unit_id`, 0 for none: 0x90a
  /// (opcode.0x90a).
  Threat(other_unit_id: Int, threat: Int)
  /// The unit is in a fight or out of one: 0x89a (opcode.0x89a).
  CombatState(in_combat: Bool)
  /// The unit's shield: 0x938 of stat 20 (opcode.0x938).
  Shield(shield: Int)
  /// The unit's current Interrupt Armor: 0x938 of stat 21 (opcode.0x938.interrupt_armor),
  /// written when the viewer's client shows the unit.
  InterruptArmor(armor: Int)
  /// The unit's absorption, the sum of its absorb pools: 0x938 of stat 22
  /// (opcode.0x938), written when the viewer's client shows the unit.
  Absorption(absorption: Int)
  /// The unit's level rose: 0x938 of stat 10 (opcode.0x938), written when the viewer's
  /// client shows the unit. A player's connection sends it for its own unit when a
  /// kill's experience crosses a level (genesis_prime/game/experience).
  Level(level: Int)
  /// The unit holds a crowd-control state: 0x87f with the instance id of the effect the
  /// caster's go listed (opcode.0x87f), written when the viewer's client shows the unit.
  CrowdControlApplied(state: CrowdControlState, instance_id: Int)
  /// The unit's crowd-control state ends: 0x880 naming the state, the cast and the
  /// instance id, with its last bit 0 (opcode.0x880), written when the viewer's client
  /// shows the unit.
  CrowdControlEnded(state: CrowdControlState, cast_id: Int, instance_id: Int)
  /// The unit holds the unit state `state`, as the `number` its creature gave this hold
  /// (genesis_prime/game/unit_state): no frame, since the client reads no row of the type;
  /// the viewer's connection keeps it in its picture of the unit, so a press that the state
  /// refuses is refused at the viewer's side too (genesis_prime/game/shown `unit_states`).
  UnitStateHeld(state: Int, number: Int)
  /// The unit's hold `number` of a unit state ends: no frame; the viewer's picture drops it.
  UnitStateEnded(number: Int)
  /// Some of the unit's properties changed, each with its base and its value as the
  /// client holds them: 0x93a (opcode.0x93a), written when the viewer's client shows
  /// the unit. A player's connection sends it for a property a lasting modifier of
  /// its own spell changed, and a creature's process for a property a modifier of a
  /// player's spell changed on it (genesis_prime/game/unit_properties).
  PropertiesChanged(properties: List(UnitProperty))
  /// The unit entered or left stealth: 0x8f5 (opcode.0x8f5), then 0x247 of type 24
  /// (opcode.0x247.type24), written when the viewer's client shows the unit. Only a
  /// player's connection sends it, for its own unit (genesis_prime/game/cast
  /// `StealthChanged`); the unit's own client gets the 0x8f5 alone, since it logs its
  /// own change.
  Stealth(stealthed: Bool)
  /// Some of the unit's item visuals changed, the slots whose shown display moved with
  /// what shows now: 0x933 (opcode.0x933), written when the viewer's client shows the
  /// unit and dropped otherwise. Only a player's connection sends it, for its own unit
  /// (genesis_prime/game/look); a viewer that first sees the unit gets the current
  /// visuals in its 0x262 instead.
  LookChanged(item_visuals: List(ItemVisual))
  /// The last source of the cast `cast_id` that the player holds from another player's
  /// cast has ended: the viewer that was listed the cast by this player's create and not
  /// told it by its caster writes a 0x811 naming the player (opcode.0x811), and any other
  /// viewer drops the news, since its caster's frames end the cast.
  HeldCastEnded(cast_id: Int)
  /// The player holds a cast of another player (the caster's go put its change on the
  /// player) that this viewer was not told by the caster: the 0x7ff and the 0x7f4 the
  /// player builds from what it holds of the cast, which a viewer that does not hold the
  /// cast writes and borrows from the player (opcode.0x7ff, opcode.0x7f4).
  HeldCastStarted(start: SpellStarted, go: SpellGo)
}
