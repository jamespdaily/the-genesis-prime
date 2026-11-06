//// Spawns for a test to stand a creature at, in World 3460, Warfare Woods, and
//// the `WorldSpawns` a world's term holds them in. The values are the client's
//// for Creature2 73464, the Virtual Battle Beast (the creature trace of the
//// combat core: level 1, faction 1441, display 26565, Base Health 52.6205
//// truncated to 52), so a test of the rule reads what the real spawn would carry
//// without the client's tables.

import class_resource_support
import database_support
import genesis_prime/content/class_resource as content_class_resource
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/hit.{Blow, Defence, Offence}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/id.{Creature2Id, Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/creature_kind.{type Kinds, Kind, Kinds}
import genesis_prime/world_map/creature_life.{
  type Attack, Attack, Attackable, Combat, Hostile,
}
import genesis_prime/world_map/game_number.{type GameNumbers, GameNumbers}
import genesis_prime/world_map/spawn.{type Row, type Spawn, Row, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object.{type StaticObject, StaticObject}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/list
import gleam/option
import owned_key
import place_support

/// Warfare Woods, WorldZone 5967 (Quest2.10518).
pub const warfare_woods = 5967

/// The game numbers migration 0010 seeds: an aggro range of 10, a leash range of
/// 55, an aggro threat of 1 and a chase stop fraction of 0.5.
pub const numbers: GameNumbers =
  GameNumbers(
    aggro_range: 10.0,
    leash_range: 55.0,
    aggro_threat: 1.0,
    chase_stop_fraction: 0.5,
  )

/// The spawn numbered `number` of a Virtual Battle Beast, `x` units along the
/// world's x axis.
pub fn battle_beast(number number: Int, x x: Float) -> Spawn {
  Spawn(
    id: SpawnId(number),
    creature_id: Creature2Id(73_464),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: warfare_woods,
      x:,
      y: 0.0,
      z: 0.0,
    ),
    level: 1,
    health: 52,
    health_source: unit_fields.ClientDefault,
    faction_id: 1441,
    base_faction_id: 1441,
    display_info_id: 26_565,
    outfit_info_id: 0,
    combat: beast_combat(),
  )
}

/// The spawn numbered `number` of a Virtual Defense Dagun, the Dominion Novice's
/// first enemy, `x` units along the world's x axis: Creature2 73465, faction 1442,
/// display 26578 of hit radius 2.0, hostile to the Dominion (1442-166 level 0) and
/// friendly to Exiles (1442-167 level 10) (`Creature2.73465`), with the Beast's
/// level, health, defence and attack but its own reach, 5.0 + 2.0.
pub fn dagun(number number: Int, x x: Float) -> Spawn {
  let beast = battle_beast(number:, x:)
  Spawn(
    ..beast,
    creature_id: Creature2Id(73_465),
    faction_id: 1442,
    base_faction_id: 1442,
    display_info_id: 26_578,
    combat: Combat(
      ..beast.combat,
      hit_radius: 2.0,
      attackable: Attackable(exile: False, dominion: True),
      hostile_to: Hostile(exile: False, dominion: True),
      attack: Attack(..beast_attack(), reach: 7.0),
    ),
  )
}

/// The static object numbered `number` of a Holoring (Creature2 73416, a type 10
/// object of world 3460's start, the trace's) standing at `place`: no recorded
/// level or health, both factions 0, display 1. A test changes what it checks by
/// record update.
pub fn holoring(number number: Int, place place: Place) -> StaticObject {
  StaticObject(
    id: SpawnId(number),
    unit_type: static_object.Simple,
    creature_id: Creature2Id(73_416),
    place:,
    level: option.None,
    health: option.None,
    faction_id: 0,
    base_faction_id: 0,
    display_info_id: 1,
    outfit_info_id: 0,
    checklist_index: 0,
    world_object_id: 0,
    world_socket_id: 0,
  )
}

/// The spawn numbered `number` of a Virtual Battle Beast standing at `place`.
pub fn beast_at(number number: Int, place place: Place) -> Spawn {
  Spawn(..battle_beast(number:, x: 0.0), place:)
}

/// A Beast standing at `place` that never deflects, so no roll of a caster's seed
/// changes what a hit does to it: every hit lands for the damage the formula gives.
pub fn beast_without_deflect_at(
  number number: Int,
  place place: Place,
) -> Spawn {
  let beast = beast_at(number:, place:)
  Spawn(
    ..beast,
    combat: Combat(
      ..beast.combat,
      defence: Defence(..beast.combat.defence, deflect_chance: 0.0),
    ),
  )
}

/// What the Virtual Battle Beast brings to a fight: the hit radius of its display, 3.0
/// (`Spell4.32812.area`); whom it may be attacked by (hostile to Exiles, `Creature2.73464`;
/// the Dominion's level is not read, and no test asserts it); whom it fights on sight:
/// Exiles, at level 0 to faction 167, and not the Dominion, at level 10 to 166
/// (Faction2Relationship 2943 and 2944, `Creature2.73464`); a deflect chance of 0.016,
/// no critical deflect, glance or mitigation (`Creature2.73464.crit_deflect_glance`,
/// `Creature2.73464.mitigation`); and its attack (`beast_attack`).
pub fn beast_combat() -> creature_life.Combat {
  Combat(
    hit_radius: 3.0,
    attackable: Attackable(exile: True, dominion: True),
    hostile_to: Hostile(exile: True, dominion: False),
    defence: Defence(
      deflect_chance: 0.016,
      crit_deflect_chance: 0.0,
      glance_chance: 0.0,
      glance_amount: 0.0,
      physical_mitigation: 0.0,
      tech_mitigation: 0.0,
      magic_mitigation: 0.0,
      shield_mitigation_max: 0.0,
    ),
    attack: beast_attack(),
    interrupt_armor: creature_life.NoArmor,
  )
}

/// The kinds migration 0010 leaves: row 0 alone, a respawn of 60 000 ms and an
/// attack of Spell4 5649 every 1500 ms.
pub fn kinds() -> Kinds {
  Kinds(
    default: Kind(
      respawn_ms: 60_000,
      attack_spell4_id: Spell4Id(5649),
      attack_interval_ms: 1500,
    ),
    by_creature: dict.new(),
  )
}

/// The Virtual Battle Beast's attack: Spell4 5649, whose effect 184741 hits for 12
/// at difficulty 1 (`Spell4Effects.184741`, `0x140565600`), Physical (damage type
/// 1), with no critical hit or strikethrough; a run speed of 10.0
/// (`Creature2.73464`, `0x1405b45e0`) and a reach of the spell's range 5.0 plus the
/// hit radius 3.0.
pub fn beast_attack() -> Attack {
  Attack(
    spell4_id: Spell4Id(5649),
    offence: Offence(
      blows: [
        Blow(
          spell4_effects_id: 184_741,
          damage_type: 1,
          damage: 12,
          delay_ms: 0,
          threat_multiplier: 1.0,
        ),
      ],
      crit_chance: 0.0,
      crit_severity: 1.0,
      strikethrough: 0.0,
    ),
    run_speed: 10.0,
    reach: 8.0,
  )
}

/// A row of the spawn table for a Virtual Battle Beast with no stats, standing
/// in World 3460 at the origin: a test changes the fields it is about with
/// record update.
pub fn beast_row(number number: Int) -> Row {
  Row(
    id: SpawnId(number),
    entity_type: 0,
    creature_id: 73_464,
    world_id: 3460,
    area_id: 0,
    x: 0.0,
    y: 0.0,
    z: 0.0,
    rotation_x: 0.0,
    rotation_y: 0.0,
    rotation_z: 0.0,
    display_info_id: 26_565,
    outfit_info_id: 0,
    faction_id: 1441,
    base_faction_id: 1441,
    checklist_index: 0,
    world_object_id: 0,
    world_socket_id: 0,
    health: option.None,
    level: option.None,
  )
}

/// The worlds the tests' maps may run in: every World row a test uses.
const worlds = [22, 51, 426, 870, 990, 1061, 1387, 3460, 3461, 6009]

/// A key whose terms hold these spawns for World 3460 and no spawn for every
/// other world a test's map may run in, as the content load leaves them. It is
/// the test's own, erased when the body ends: a test with no spawns takes
/// `key_without_spawns` and puts nothing.
pub fn key_with(
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
) -> table_store.Key {
  key_in(world_id: 3460, spawns:, respawn_ms:)
}

/// The same with the spawns in the term of the World row `world_id`, which a test's
/// players are in when they are not in World 3460.
pub fn key_in(
  world_id spawns_world: Int,
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
) -> table_store.Key {
  let key = owned_key.new_fixture_key()
  put_worlds(key:, spawns_world:, spawns:, respawn_ms:)
  key
}

/// The key every test with no spawns shares: the terms are put once per run and
/// never erased, as the content load leaves them for a database with no spawn.
pub fn key_without_spawns() -> table_store.Key {
  database_support.once("spawn_support_key_without_spawns", fn() {
    let key = owned_key.new_shared_key()
    put_worlds(key:, spawns_world: 3460, spawns: [], respawn_ms: 60_000)
    key
  })
}

fn put_worlds(
  key key: table_store.Key,
  spawns_world spawns_world: Int,
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
) -> Nil {
  content_game_number.put(key:, numbers:)
  content_class_resource.put(key:, classes: class_resource_support.classes())
  content_creature_kind.put(
    key:,
    kinds: Kinds(
      default: Kind(
        respawn_ms:,
        attack_spell4_id: Spell4Id(5649),
        attack_interval_ms: 1500,
      ),
      by_creature: dict.new(),
    ),
  )
  list.each(worlds, fn(world_id) {
    content_spawn.put_world(
      key:,
      world_id:,
      spawns: case world_id == spawns_world {
        True -> spawn.world_spawns(spawns:, objects: [])
        False -> spawn.no_spawns()
      },
    )
  })
}

/// The offence with every blow dealing `damage`: planted test data, for a fight
/// whose test is of a death, not of the number.
pub fn dealing(
  offence offence: hit.Offence,
  damage damage: Int,
) -> hit.Offence {
  Offence(
    ..offence,
    blows: list.map(offence.blows, fn(blow) { Blow(..blow, damage:) }),
  )
}

/// The spawn with every blow of its attack dealing `damage` (`dealing`).
pub fn spawn_dealing(spawn spawn: Spawn, damage damage: Int) -> Spawn {
  let attack = spawn.combat.attack
  Spawn(
    ..spawn,
    combat: Combat(
      ..spawn.combat,
      attack: Attack(
        ..attack,
        offence: dealing(offence: attack.offence, damage:),
      ),
    ),
  )
}
