//// What the tests of the map's rule share: the map's realm, a map with no
//// players and a character of a known look.

import character_support
import character_tables
import genesis_prime/store.{type Character, Character}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature_kind.{type Kinds, Kind, Kinds}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/static_object.{type StaticObject}
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict
import gleam/list
import spawn_support

/// The map's realm: not 1, so a unit built with a fixed realm fails.
pub const realm_id = 7

/// How long a spawn whose creature crashed stays empty in the tests' maps: the
/// server's 60 s respawn, the default kind's.
pub const respawn_ms = 60_000

/// How long a creature no player sees keeps running in the tests' maps, and
/// how often the map looks for one: the server's 60 s and 10 s. A rule's test
/// drives the clock through the inputs' times, so it waits for neither.
pub const idle_stop_ms = 60_000

pub const sweep_ms = 10_000

/// A map of the World table's row 3460 with no players, run as `incarnation`.
pub fn empty(incarnation incarnation: Int) -> State {
  standing(incarnation:, spawns: [])
}

/// A map of the World table's row 3460 with no players that stands a creature at
/// each of the spawns, run as `incarnation`.
pub fn standing(
  incarnation incarnation: Int,
  spawns spawns: List(Spawn),
) -> State {
  standing_with(
    incarnation:,
    spawns:,
    kinds: Kinds(
      default: Kind(
        respawn_ms:,
        attack_spell4_id: Spell4Id(5649),
        attack_interval_ms: 1500,
        cast_ms: 0,
      ),
      by_creature: dict.new(),
    ),
  )
}

/// The same map with the kinds the test chooses.
pub fn standing_with(
  incarnation incarnation: Int,
  spawns spawns: List(Spawn),
  kinds kinds: Kinds,
) -> State {
  with_objects(incarnation:, spawns:, objects: [], kinds:)
}

/// The same map with these static objects in its world too.
pub fn with_objects(
  incarnation incarnation: Int,
  spawns spawns: List(Spawn),
  objects objects: List(StaticObject),
  kinds kinds: Kinds,
) -> State {
  with_summons(
    incarnation:,
    spawns:,
    objects:,
    kinds:,
    summons: spawn_support.summon_checks(),
  )
}

/// The same map whose development summons are checked with `summons`.
pub fn with_summons(
  incarnation incarnation: Int,
  spawns spawns: List(Spawn),
  objects objects: List(StaticObject),
  kinds kinds: Kinds,
  summons summons: spawn.SummonChecks,
) -> State {
  map.new(map.Settings(
    map: MapId(world_id: 3460, instance: 0),
    incarnation:,
    realm_id:,
    tables: character_tables.shared(),
    spawns: spawn.world_spawns(spawns:, objects:),
    summons:,
    kinds:,
    numbers: spawn_support.numbers,
    idle_stop_ms:,
    sweep_ms:,
  ))
}

/// A Dominion human male whose id is `number`, with the look of
/// CharacterCustomization row 10. Its saved place is not the place a Join
/// carries, which is the place the unit is made at.
pub fn character(number number: Int) -> Character {
  Character(
    ..character_support.character(number:),
    look: character_tables.row_10_look(),
  )
}

/// The stay a connection's `count`th join names: the one after `count - 1` others
/// (genesis_prime/world_map/stay).
pub fn stay(count count: Int) -> Stay {
  list.fold(list.repeat(Nil, count), stay.none_yet(), fn(earlier, _) {
    stay.next(earlier)
  })
}
